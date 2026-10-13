"""CloudShirt order insights API.

Serves a summary of the order exports that the REQ-07 export script (or any
upload) places under ``orders/`` in the S3 bucket, behind API Gateway.

Deliberately reads S3 rather than Amazon RDS: the database sits in private
subnets and its schema is created out of band (the CloudShirt app seeds but
never runs EF Core migrations), so reading the exports keeps this component
working regardless of the database's state.
"""

import csv
import io
import json
import os
from decimal import Decimal, InvalidOperation

import boto3

ENV_BUCKET = "ORDER_EXPORT_BUCKET"
ORDERS_PREFIX = "exports/orders/"
TOP_PRODUCTS = 5
MAX_OBJECT_BYTES = 100 * 1024 * 1024

# Canonical column -> accepted header spellings, compared after normalising
# (lowercase, all non-alphanumeric characters removed). bcp and SSMS exports
# rarely spell things the way the contract does, so each column accepts the
# spellings it realistically arrives as.
COLUMNS = {
    "OrderId": ("orderid", "id", "salesorderid", "order"),
    "BuyerId": ("buyerid", "customerid", "userid"),
    "ProductName": ("productname", "product", "itemname", "name"),
    "UnitPrice": ("unitprice", "price", "itemprice"),
    "Quantity": ("quantity", "qty", "units"),
}

S3 = boto3.client("s3")


def _normalise(name):
    return "".join(c for c in (name or "").strip().lower() if c.isalnum())


def _resolve(header):
    """Map canonical columns onto header positions, first match wins."""
    normalised = [_normalise(cell) for cell in header]
    found = {}
    for canonical, aliases in COLUMNS.items():
        for position, value in enumerate(normalised):
            if value == _normalise(canonical) or value in aliases:
                found[canonical] = position
                break
    return found


def _decimal(value):
    """Parse a decimal, rejecting the non-finite values Decimal accepts.

    Decimal("Infinity") parses happily and would otherwise leak inf into the
    revenue total, which json.dumps renders as bare Infinity - not valid JSON.
    """
    try:
        parsed = Decimal((value or "").strip())
    except (InvalidOperation, ValueError):
        return None
    return parsed if parsed.is_finite() else None


def _integer(value):
    parsed = _decimal(value)
    if parsed is None:
        return None
    try:
        return int(parsed)
    except (OverflowError, ValueError):
        return None


def summarise(csv_text, source_key):
    """Summarise one exported orders CSV. Bad input yields an error, not a raise."""
    reader = csv.reader(io.StringIO(csv_text))
    try:
        header = next(reader)
    except StopIteration:
        return {"sourceKey": source_key, "error": "empty_file"}

    columns = _resolve(header)
    if "OrderId" not in columns:
        return {"sourceKey": source_key, "error": "missing_order_id"}

    rows = skipped = 0
    orders, buyers = set(), set()
    units = 0
    revenue = Decimal("0")
    products = {}

    for raw in reader:
        if not raw or all(not (cell or "").strip() for cell in raw):
            continue

        def cell(name):
            position = columns.get(name)
            if position is None or position >= len(raw):
                return ""
            return (raw[position] or "").strip()

        order_id = cell("OrderId")
        if not order_id:
            skipped += 1
            continue

        rows += 1
        orders.add(order_id)
        malformed = False

        if "BuyerId" in columns and cell("BuyerId"):
            buyers.add(cell("BuyerId"))

        quantity = None
        if "Quantity" in columns:
            quantity = _integer(cell("Quantity"))
            if quantity is None and cell("Quantity"):
                malformed = True

        price = None
        if "UnitPrice" in columns:
            price = _decimal(cell("UnitPrice"))
            if price is None and cell("UnitPrice"):
                malformed = True

        if quantity is not None:
            units += quantity

        if quantity is not None and price is not None:
            line_total = price * quantity
            revenue += line_total
            if "ProductName" in columns:
                name = cell("ProductName") or "(unknown)"
                entry = products.setdefault(name, [0, Decimal("0")])
                entry[0] += quantity
                entry[1] += line_total

        if malformed:
            skipped += 1

    unavailable = []
    if "BuyerId" not in columns:
        unavailable.append("buyers")
    if "Quantity" not in columns:
        unavailable.append("units")
    if "UnitPrice" not in columns or "Quantity" not in columns:
        unavailable.append("revenue")
    if "ProductName" not in columns or "Quantity" not in columns:
        unavailable.append("topProducts")

    top = sorted(
        ({"name": name, "units": data[0], "revenue": float(data[1])} for name, data in products.items()),
        key=lambda item: (-item["units"], -item["revenue"], item["name"]),
    )[:TOP_PRODUCTS]

    return {
        "sourceKey": source_key,
        "rows": rows,
        "skippedRows": skipped,
        "orders": len(orders),
        "buyers": len(buyers) if "BuyerId" in columns else None,
        "units": units if "Quantity" in columns else None,
        "revenue": float(revenue) if "UnitPrice" in columns and "Quantity" in columns else None,
        "topProducts": top or None,
        "unavailableMetrics": unavailable,
    }


def _id_from_key(key):
    """Short identifier for an export, used by the /exports/{id} route.

    The REQ-07 script names its files orders_YYYYMMDD_HHMMSS.csv, one per run.
    An export produced by hand may instead be named orders-YYYY-MM-DD.csv, so
    both spellings are accepted and anything else falls back to the file stem.
    """
    name = (key or "").rsplit("/", 1)[-1]
    if not name.lower().endswith(".csv"):
        return None
    stem = name[:-len(".csv")]
    for prefix in ("orders_", "orders-"):
        if stem.startswith(prefix):
            stem = stem[len(prefix):]
            break
    return stem or None


def _reply(status, payload):
    return {
        "statusCode": status,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(payload, indent=2),
    }


def _read(key):
    """Fetch an object, refusing anything oversized before decoding it."""
    body = S3.get_object(Bucket=os.environ[ENV_BUCKET], Key=key)["Body"].read(MAX_OBJECT_BYTES + 1)
    if len(body) > MAX_OBJECT_BYTES:
        raise ValueError("object exceeds the 100 MB limit")
    return body.decode("utf-8-sig")


def handler(event, context):
    bucket = os.environ[ENV_BUCKET]
    path = (event.get("path") or "/").rstrip("/") or "/"

    if path == "/health":
        return _reply(200, {"service": "CloudShirt-Order-Insights", "bucket": bucket})

    if path == "/exports":
        listing = S3.list_objects_v2(Bucket=bucket, Prefix=ORDERS_PREFIX).get("Contents") or []
        return _reply(200, {
            "count": len(listing),
            "exports": [
                {
                    "key": item["Key"],
                    "id": _id_from_key(item["Key"]),
                    "size": item.get("Size"),
                    "lastModified": item["LastModified"].isoformat(),
                }
                for item in listing
            ],
        })

    if path.startswith("/exports/"):
        wanted = path[len("/exports/"):]
        listing = S3.list_objects_v2(Bucket=bucket, Prefix=ORDERS_PREFIX).get("Contents") or []
        key = next((item["Key"] for item in listing if _id_from_key(item["Key"]) == wanted), None)
        if key is None:
            return _reply(404, {
                "error": "not_found",
                "message": "No export with that id. GET /exports lists the available ones.",
                "id": wanted,
            })
        try:
            return _reply(200, summarise(_read(key), key))
        except ValueError as exc:
            return _reply(413, {"error": "object_too_large", "key": key, "message": str(exc)})

    if path == "/summary":
        listing = S3.list_objects_v2(Bucket=bucket, Prefix=ORDERS_PREFIX).get("Contents") or []
        per_export, failed = [], []
        for item in listing:
            try:
                summary = summarise(_read(item["Key"]), item["Key"])
            except Exception:  # unreadable export is reported, not fatal
                failed.append(item["Key"])
                continue
            if summary.get("error"):
                failed.append(item["Key"])
                continue
            summary["exportId"] = _id_from_key(item["Key"])
            summary["key"] = item["Key"]
            per_export.append(summary)

        per_export.sort(key=lambda export: export["exportId"] or "")

        def total(field):
            """Sum across exports, or None when any export lacks the metric.

            Summing None as zero would report "0 units" for an export that
            simply has no quantity column, which reads as a real measurement.
            """
            values = [export[field] for export in per_export]
            if not values or any(value is None for value in values):
                return None
            return sum(values)

        revenue_total = total("revenue")

        return _reply(200, {
            "exportCount": len(per_export),
            "failedExports": failed,
            "totals": {
                "rows": total("rows"),
                "orders": total("orders"),
                "units": total("units"),
                "revenue": round(revenue_total, 2) if revenue_total is not None else None,
            },
            "perExport": [
                {field: export[field] for field in ("exportId", "key", "rows", "orders", "units", "revenue")}
                for export in per_export
            ],
        })

    return _reply(404, {"error": "not_found", "path": path})
