from __future__ import annotations

import json
import re
import unicodedata
import zipfile
from pathlib import Path
from xml.etree import ElementTree

NS = {"x": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}

IMPOT = "Imp\u00f4t"
TAXE = "Taxe"
REDEVANCE = "Redevance"


def main() -> None:
    source = Path("assets/tariffs/Liste_Tarifaire.xlsx")
    target = Path("assets/tariffs/official_tariffs.json")
    items: list[dict[str, object]] = []

    with zipfile.ZipFile(source) as workbook:
        add_vehicle_tariffs(
            workbook,
            sheet_path="xl/worksheets/sheet1.xml",
            sheet_name="V\u00e9hicules - Pers. Morales",
            taxpayer_type="Personnes morales",
            items=items,
        )
        add_vehicle_tariffs(
            workbook,
            sheet_path="xl/worksheets/sheet2.xml",
            sheet_name="V\u00e9hicules - Pers. Physiques",
            taxpayer_type="Personnes physiques",
            items=items,
        )
        add_property_tariffs(workbook, items)
        add_rental_income_tariffs(workbook, items)
        add_firefighter_tariffs(workbook, items)

    target.write_text(
        json.dumps(items, ensure_ascii=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {len(items)} official tariffs to {target}")


def add_vehicle_tariffs(
    workbook: zipfile.ZipFile,
    *,
    sheet_path: str,
    sheet_name: str,
    taxpayer_type: str,
    items: list[dict[str, object]],
) -> None:
    for row in read_rows(workbook, sheet_path):
        vehicle_category = cell_text(row, 0)
        if (
            vehicle_category is None
            or vehicle_category.startswith("Taux ")
            or vehicle_category.startswith("Cat\u00e9gories ")
        ):
            continue

        vehicle_details = f"{taxpayer_type} - {vehicle_category}"
        vehicle_source = f"{sheet_name} - v\u00e9hicule"

        vehicle_tax = cell_number(row, 1)
        if vehicle_tax is not None and vehicle_tax > 0:
            add_item(
                items,
                receipt_type=IMPOT,
                label=f"Imp\u00f4t sur les v\u00e9hicules - {vehicle_details}",
                source=vehicle_source,
                details=vehicle_details,
                tariff_label=f"{format_usd_amount(vehicle_tax)} USD",
                amount_usd=vehicle_tax,
            )

        traffic_tax = cell_number(row, 2)
        if traffic_tax is not None and traffic_tax > 0:
            add_item(
                items,
                receipt_type=TAXE,
                label=f"Taxe sp\u00e9ciale de circulation - {vehicle_details}",
                source=vehicle_source,
                details=vehicle_details,
                tariff_label=f"{format_usd_amount(traffic_tax)} USD",
                amount_usd=traffic_tax,
            )

        fee = cell_number(row, 3)
        if fee is not None and fee > 0:
            add_item(
                items,
                receipt_type=REDEVANCE,
                label=f"Redevance v\u00e9hicules - {vehicle_details}",
                source=vehicle_source,
                details=vehicle_details,
                tariff_label=f"{format_usd_amount(fee)} USD",
                amount_usd=fee,
            )

        printed_form = cell_number(row, 4)
        if printed_form is not None and printed_form > 0:
            add_item(
                items,
                receipt_type=REDEVANCE,
                label=f"Imprim\u00e9 v\u00e9hicules - {vehicle_details}",
                source=vehicle_source,
                details=vehicle_details,
                tariff_label=f"{format_usd_amount(printed_form)} USD",
                amount_usd=printed_form,
            )


def add_property_tariffs(
    workbook: zipfile.ZipFile,
    items: list[dict[str, object]],
) -> None:
    sheet_name = "Imp\u00f4t Foncier"
    for row in read_rows(workbook, "xl/worksheets/sheet3.xml"):
        property_nature = cell_text(row, 0)
        locality_rank = cell_text(row, 1)
        if (
            property_nature is None
            or locality_rank is None
            or property_nature.startswith("Taux ")
            or property_nature.startswith("Nature ")
        ):
            continue

        moral_rate = cell_text(row, 2)
        if moral_rate:
            add_item(
                items,
                receipt_type=IMPOT,
                label=(
                    "Imp\u00f4t foncier - Personne morale - "
                    f"{property_nature} - {locality_rank}"
                ),
                source=sheet_name,
                details=f"{property_nature} - {locality_rank} - Personne morale",
                tariff_label=moral_rate,
                amount_usd=fixed_dollar_amount(moral_rate),
            )

        physical_rate = cell_text(row, 3)
        if physical_rate:
            add_item(
                items,
                receipt_type=IMPOT,
                label=(
                    "Imp\u00f4t foncier - Personne physique - "
                    f"{property_nature} - {locality_rank}"
                ),
                source=sheet_name,
                details=f"{property_nature} - {locality_rank} - Personne physique",
                tariff_label=physical_rate,
                amount_usd=fixed_dollar_amount(physical_rate),
            )


def add_rental_income_tariffs(
    workbook: zipfile.ZipFile,
    items: list[dict[str, object]],
) -> None:
    sheet_name = "Revenus Locatifs"
    for row in read_rows(workbook, "xl/worksheets/sheet4.xml"):
        locality_rank = cell_text(row, 0)
        rent_range = cell_text(row, 1)
        if (
            locality_rank is None
            or rent_range is None
            or locality_rank.startswith("Imp\u00f4t ")
            or locality_rank.startswith("Rang ")
        ):
            continue

        irl_rate = cell_text(row, 2)
        if irl_rate:
            add_item(
                items,
                receipt_type=IMPOT,
                label=(
                    "Imp\u00f4t sur les revenus locatifs - "
                    f"{locality_rank} - {rent_range}"
                ),
                source=sheet_name,
                details=f"{locality_rank} - {rent_range}",
                tariff_label=irl_rate,
            )

        retention_rate = cell_text(row, 3)
        if retention_rate:
            add_item(
                items,
                receipt_type=TAXE,
                label=f"Retenue locative - {locality_rank} - {rent_range}",
                source=sheet_name,
                details=f"{locality_rank} - {rent_range}",
                tariff_label=retention_rate,
            )


def add_firefighter_tariffs(
    workbook: zipfile.ZipFile,
    items: list[dict[str, object]],
) -> None:
    sheet_name = "Sapeurs-Pompiers & Extincteurs"
    for row in read_rows(workbook, "xl/worksheets/sheet5.xml"):
        service = cell_text(row, 0)
        specification = cell_text(row, 1)
        tariff = cell_text(row, 2)
        periodicity = cell_text(row, 3)
        if (
            service is None
            or tariff is None
            or service.startswith("Tarification ")
            or service.startswith("Nature ")
        ):
            continue

        has_specification = specification not in (None, "", "-")
        label = f"{service} - {specification}" if has_specification else service
        details = " - ".join(
            part
            for part in [
                f"Sp\u00e9cification: {specification}" if has_specification else "",
                f"P\u00e9riodicit\u00e9: {periodicity}" if periodicity else "",
            ]
            if part
        )

        add_item(
            items,
            receipt_type=REDEVANCE,
            label=label,
            source=sheet_name,
            details=details or sheet_name,
            tariff_label=tariff,
            amount_usd=fixed_dollar_amount(tariff),
        )


def add_item(
    items: list[dict[str, object]],
    *,
    receipt_type: str,
    label: str,
    source: str,
    details: str,
    tariff_label: str,
    amount_usd: float | None = None,
) -> None:
    item: dict[str, object] = {
        "id": f"{slugify(receipt_type)}-{len(items)}",
        "receiptType": receipt_type,
        "label": label,
        "source": source,
        "details": details,
        "tariffLabel": tariff_label,
    }
    if amount_usd is not None:
        item["amountUsd"] = amount_usd
    items.append(item)


def read_rows(workbook: zipfile.ZipFile, sheet_path: str) -> list[list[str | None]]:
    root = ElementTree.fromstring(workbook.read(sheet_path))
    rows: list[list[str | None]] = []
    for row in root.findall(".//x:sheetData/x:row", NS):
        values: dict[int, str | None] = {}
        for cell in row.findall("x:c", NS):
            ref = cell.get("r", "")
            if not ref:
                continue
            values[column_index(ref)] = read_cell(cell)
        if values:
            rows.append([values.get(i) for i in range(max(values) + 1)])
    return rows


def read_cell(cell: ElementTree.Element) -> str | None:
    if cell.get("t") == "inlineStr":
        value = "".join(
            text_node.text or ""
            for text_node in cell.findall(".//x:is//x:t", NS)
        ).strip()
        return value or None
    value_node = cell.find("x:v", NS)
    if value_node is None or value_node.text is None:
        return None
    value = value_node.text.strip()
    return value or None


def column_index(cell_ref: str) -> int:
    letters = "".join(char for char in cell_ref if char.isalpha())
    index = 0
    for char in letters.upper():
        index = index * 26 + ord(char) - ord("A") + 1
    return index - 1


def cell_text(row: list[str | None], index: int) -> str | None:
    if index >= len(row):
        return None
    value = row[index]
    if value is None:
        return None
    value = value.strip()
    return value if value and value != "null" else None


def cell_number(row: list[str | None], index: int) -> float | None:
    value = cell_text(row, index)
    if value is None:
        return None
    try:
        return float(value.replace(",", "."))
    except ValueError:
        return None


def fixed_dollar_amount(value: str) -> float | None:
    lower = value.lower()
    if (
        "%"
        in lower
        or "/"
        in lower
        or "+"
        in lower
        or "\u00e0" in lower
    ):
        return None

    matches = re.findall(r"\d+(?:[ \u00a0]\d{3})*(?:[,.]\d+)?", value)
    if len(matches) != 1:
        return None

    normalized = matches[0].replace(" ", "").replace("\u00a0", "").replace(",", ".")
    try:
        return float(normalized)
    except ValueError:
        return None


def format_usd_amount(value: float) -> str:
    if value == round(value):
        return str(int(value))
    return f"{value:.2f}".removesuffix("0")


def slugify(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    ascii_value = normalized.encode("ascii", "ignore").decode("ascii")
    return re.sub(r"[^a-z0-9]+", "-", ascii_value.lower()).strip("-")


if __name__ == "__main__":
    main()
