#!/usr/bin/env python3
"""
Normalisiert eine von Trivy erzeugte CycloneDX-SBOM zu einem stabilen
Komponenten-Inventar: entfernt build-/zeitabhängige Felder (Seriennummer,
Zeitstempel, Image-Digest, eingebettete Schwachstellen) und sortiert die
Komponenten deterministisch. So ändert sich die abgelegte SBOM nur, wenn sich
die tatsächliche Software-Zusammensetzung ändert – nicht bei jedem Build oder
jeder neu veröffentlichten CVE.

Normalises a Trivy-generated CycloneDX SBOM into a stable component inventory:
strips build/time-dependent fields (serial number, timestamp, image digest,
embedded vulnerabilities) and sorts components deterministically, so the stored
SBOM only changes when the actual software composition changes.

Usage: normalize-sbom.py <sbom.json> <canonical-name>
"""
import json
import sys

path, name = sys.argv[1], sys.argv[2]


def strip_arch(purl):
    """Entfernt den arch-Qualifier aus einer purl (arch-agnostisch, damit
    dev/amd64/arm64 identische SBOMs ergeben).
    Removes the arch qualifier from a purl (arch-agnostic, so dev/amd64/arm64
    yield identical SBOMs)."""
    if not purl or "?" not in purl:
        return purl
    base, qual = purl.split("?", 1)
    kept = [kv for kv in qual.split("&") if not kv.startswith("arch=")]
    return base + ("?" + "&".join(kept) if kept else "")


with open(path) as fh:
    doc = json.load(fh)

doc.pop("serialNumber", None)
doc.pop("vulnerabilities", None)
doc.pop("dependencies", None)
doc.get("metadata", {}).pop("timestamp", None)
# Kanonische Wurzelkomponente ohne Digest / canonical root component without digest
doc.setdefault("metadata", {})["component"] = {
    "type": "container",
    "name": name,
    "bom-ref": name,
}


def clean(component):
    """arch aus purl/bom-ref entfernen und build-spezifische properties
    (Layer-Digests etc.) verwerfen.
    Strip arch from purl/bom-ref and drop build-specific properties
    (layer digests etc.)."""
    component["bom-ref"] = strip_arch(component.get("bom-ref", ""))
    if "purl" in component:
        component["purl"] = strip_arch(component["purl"])
    component.pop("properties", None)
    return component


# Nur stabile (purl-basierte) Komponenten behalten, bereinigt und sortiert
# Keep only stable (purl-based) components, cleaned and sorted
doc["components"] = sorted(
    (clean(c) for c in doc.get("components", []) if str(c.get("bom-ref", "")).startswith("pkg:")),
    key=lambda c: c["bom-ref"],
)

with open(path, "w") as fh:
    json.dump(doc, fh, indent=2, ensure_ascii=False, sort_keys=True)
    fh.write("\n")

print(f"{path}: {len(doc['components'])} components (normalised, name={name})")
