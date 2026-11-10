#!/usr/bin/env python3
"""Builds the production deploy folder (docs/production-deployment.md).

Copies force-app into build/prod and applies the production-only changes:
  * standard value sets merged with the ones retrieved from production (E14: never a partial set);
  * Cardcom_Setting.Default filled from a local values file (kept out of Git), or left out;
  * Donor_Link_Setting.Default (the donor-link secret) only on the first install;
  * the legacy record type / sales process left out (D34: the code doesn't use them);
  * optional: no translations, no field-history tracking on Opportunity.
Then writes manifest/package.xml (needs the sf CLI) and the list of test classes.

Nothing here talks to an org. Usage: see --help.
"""
import argparse
import json
import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "force-app" / "main" / "default"
NEW_STAGES = ["Pending_Verification", "Active", "Stopped", "Cancelled", "Verification_Failed"]
SVS_NAMES = ["OpportunityStage", "ContactRole", "OpportunityType"]
# Cardcom_Setting__mdt fields that must hold a production value before go-live.
REQUIRED = ["Terminal_Number__c", "Webhook_Url__c", "Allowed_Return_Hosts__c", "Donor_Portal_Base_Url__c",
            "Org_Wide_Email_Address__c", "Failure_Notify_Emails__c", "Integration_User_Id__c", "Terms_Url__c"]
PLACEHOLDERS = ["ORG.org.il", "https://ORG/", "https://ORG.", "example.org", "example.com"]
NUMERIC = {"Terminal_Number__c", "Secondary_Terminal_Number__c", "Batch_Size__c", "Currency_Iso__c", "Lp_JValidate_Type__c", "Max_Amount__c",
           "Min_Amount__c", "Recon_Page_Size__c"}
BOOLEAN = {"Holiday_Auto_Detect__c", "Is_Recurring_Terminal__c", "Secondary_Is_Recurring_Terminal__c", "Optional_Verify_On_Open__c",
           "Receipt_Link_Deal_Numbers__c", "Recon_Report_Unknown__c", "Send_Donor_Charge_Email__c"}


ALLOW_PLACEHOLDERS = False


def die_or_warn(msg):
    """--allow-placeholders: deploy now, fill the missing values in Setup before go-live."""
    if ALLOW_PLACEHOLDERS:
        print("  WARNING: " + msg + " (allowed by --allow-placeholders: fix it in Setup before go-live)")
    else:
        die(msg)


def die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


def value_blocks(xml):
    """{fullName: '<standardValue>…</standardValue>'} in file order."""
    out = {}
    for m in re.finditer(r"[ \t]*<standardValue>.*?</standardValue>\n?", xml, re.S):
        name = re.search(r"<fullName>(.*?)</fullName>", m.group(0)).group(1)
        out[name] = m.group(0)
    return out


def find_org_svs(org_dir, name):
    hits = [p for p in pathlib.Path(org_dir).rglob(name + ".standardValueSet*") if p.is_file()]
    return hits[0] if hits else None


def merge_svs(out_default, org_dir, first_install):
    for name in SVS_NAMES:
        ours_path = out_default / "standardValueSets" / (name + ".standardValueSet-meta.xml")
        org_path = find_org_svs(org_dir, name)
        if org_path is None:
            die(f"{name} not found under {org_dir}; retrieve it from production first (manifest/retrieve-standard-value-sets.xml)")
        ours = value_blocks(ours_path.read_text(encoding="utf-8"))
        org_xml = org_path.read_text(encoding="utf-8")
        org = value_blocks(org_xml)
        org_lower = {k.lower(): k for k in org}
        if name == "OpportunityStage" and first_install:
            clash = [s for s in NEW_STAGES if s.lower() in org_lower]
            if clash:
                die(f"production already has the stage(s) {clash} (E14): stop and decide with the client before deploying")
        missing = [k for k in ours if k.lower() not in org_lower]
        if name == "OpportunityStage":
            missing = [k for k in missing if k in NEW_STAGES]
        elif name == "ContactRole":
            missing = [k for k in missing if k == "Donor"]
        else:
            missing = [k for k in missing if k == "Daily Donation Pledge"]
        add = "".join(ours[k] for k in missing)
        last = org_xml.rfind("</standardValue>")
        if last < 0:
            die(f"{org_path} has no values; it doesn't look like a retrieved {name}")
        cut = last + len("</standardValue>")
        merged = org_xml[:cut] + "\n" + add.rstrip("\n") + org_xml[cut:] if add else org_xml
        ours_path.write_text(merged, encoding="utf-8")
        print(f"  {name}: kept {len(org)} production values, added {missing or 'nothing'}")


def fill_settings(out_default, values_path):
    rec = out_default / "customMetadata" / "Cardcom_Setting.Default.md-meta.xml"
    labels_file = out_default / "labels" / "CustomLabels.labels-meta.xml"
    if values_path is None:
        rec.unlink()
        labels_file.unlink()
        print("  Cardcom_Setting.Default + custom labels: LEFT OUT (no --values); production keeps the values set in Setup")
        return
    vals = json.loads(pathlib.Path(values_path).read_text(encoding="utf-8-sig"))  # Notepad may add a BOM
    labels = vals.pop("labels", {}) or {}
    vals = {k: v for k, v in vals.items() if not k.startswith("_")}
    fill_labels(labels_file, labels, values_path)
    xml = rec.read_text(encoding="utf-8")
    for field, v in vals.items():
        pat = re.compile(r"(<field>" + re.escape(field) + r"</field>\s*)<value[^>]*?(?:/>|>.*?</value>)", re.S)
        if not pat.search(xml):
            die(f"{values_path}: {field} is not a Cardcom_Setting__mdt field in the record")
        if v is None or v == "":
            new = '<value xsi:nil="true"/>'
        elif field in BOOLEAN:
            new = '<value xsi:type="xsd:boolean">' + ("true" if v is True or str(v).lower() == "true" else "false") + "</value>"
        elif field in NUMERIC:
            new = '<value xsi:type="xsd:double">' + str(float(v)) + "</value>"
        else:
            s = str(v).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            new = '<value xsi:type="xsd:string">' + s + "</value>"
        xml = pat.sub(lambda m: m.group(1) + new, xml, count=1)
    rec.write_text(xml, encoding="utf-8")
    empty = [f for f in REQUIRED if re.search(r"<field>" + f + r"</field>\s*<value xsi:nil", xml)]
    bad = [p for p in PLACEHOLDERS + ["&lt;"] if p in xml]
    if empty or bad:
        die_or_warn(f"Cardcom_Setting.Default still has empty {empty} / placeholders {bad}; fix {values_path}")
    print(f"  Cardcom_Setting.Default: filled {len(vals)} fields from {values_path}")


LABEL_PLACEHOLDERS = ["example.org", "03-0000000", "שם הארגון", "צוות הארגון"]


def fill_labels(labels_file, labels, values_path):
    """Custom labels used in the donor e-mails (B6.9.3): org name, contact phone/e-mail, signer, impact sentence."""
    xml = labels_file.read_text(encoding="utf-8")
    for name, v in labels.items():
        pat = re.compile(r"(<fullName>" + re.escape(name) + r"</fullName>.*?<value>).*?(</value>)", re.S)
        if not pat.search(xml):
            die(f"{values_path}: label {name} doesn't exist in CustomLabels")
        s = str(v).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        xml = pat.sub(lambda m: m.group(1) + s + m.group(2), xml, count=1)
    labels_file.write_text(xml, encoding="utf-8")
    bad = [p for p in LABEL_PLACEHOLDERS if p in xml]
    if bad:
        die_or_warn(f"custom labels still hold placeholders {bad}; add them under \"labels\" in {values_path}")
    print(f"  custom labels: filled {len(labels)} from {values_path}")


def strip_record_type(out_default):
    opp = out_default / "objects" / "Opportunity"
    for d in ("recordTypes", "businessProcesses"):
        shutil.rmtree(opp / d, ignore_errors=True)
    tr = out_default / "objectTranslations" / "Opportunity-iw" / "Opportunity-iw.objectTranslation-meta.xml"
    if tr.exists():
        tr.write_text(re.sub(r"[ \t]*<recordTypes>.*?</recordTypes>\n?", "", tr.read_text(encoding="utf-8"), flags=re.S),
                      encoding="utf-8")
    lay = out_default / "layouts" / "Opportunity-Micro Donation Pledge Layout.layout-meta.xml"
    if lay.exists():
        lay.write_text(re.sub(r"[ \t]*<layoutItems>\s*<behavior>\w+</behavior>\s*<field>RecordTypeId</field>\s*</layoutItems>\n?", "",
                              lay.read_text(encoding="utf-8")), encoding="utf-8")
    print("  record type Micro_Donation_Pledge + sales process Micro_Donation_Process: LEFT OUT (D34); RecordTypeId off the layout")


def make_cmdt_public(out_default):
    """Production (not a developer/sandbox/scratch org) refuses Protected custom metadata types outside a managed package.
    In an unmanaged org Protected hides nothing from admins anyway; the secret stays in Setup only."""
    obj = out_default / "objects" / "Donor_Link_Setting__mdt" / "Donor_Link_Setting__mdt.object-meta.xml"
    obj.write_text(obj.read_text(encoding="utf-8").replace("<visibility>Protected</visibility>", "<visibility>Public</visibility>"),
                   encoding="utf-8")
    rec = out_default / "customMetadata" / "Donor_Link_Setting.Default.md-meta.xml"
    if rec.exists():
        rec.write_text(rec.read_text(encoding="utf-8").replace("<protected>true</protected>", "<protected>false</protected>"),
                       encoding="utf-8")
    print("  Donor_Link_Setting__mdt: visibility Public (production refuses Protected)")


def write_phase1(out, out_default):
    """Validation rules read $CustomMetadata.Cardcom_Setting__mdt.Default, which must exist before the main deploy:
    phase 1 = the custom metadata types and their records only (no Apex, deploys with the default test level)."""
    p1 = out.parent / (out.name + "-phase1")
    shutil.rmtree(p1, ignore_errors=True)
    d1 = p1 / "force-app" / "main" / "default"
    (d1 / "objects").mkdir(parents=True)
    for o in (out_default / "objects").glob("*__mdt"):
        shutil.copytree(o, d1 / "objects" / o.name)
    shutil.copytree(out_default / "customMetadata", d1 / "customMetadata")
    shutil.copy(out / "sfdx-project.json", p1)
    print(f"  phase 1 (custom metadata types + records) -> {p1}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--org-svs", help="folder retrieved from production with manifest/retrieve-standard-value-sets.xml")
    ap.add_argument("--skip-svs", action="store_true", help="leave the standard value sets out (redeploy, nothing changed there)")
    ap.add_argument("--values", help="local JSON with production Cardcom_Setting__mdt values (config/prod-values.local.json)")
    ap.add_argument("--first-install", action="store_true", help="include Donor_Link_Setting.Default (empty secret, set it in Setup)")
    ap.add_argument("--with-record-type", action="store_true", help="also deploy record type Micro_Donation_Pledge + its sales process")
    ap.add_argument("--no-translations", action="store_true", help="leave out the Hebrew translations (Translation Workbench off)")
    ap.add_argument("--no-history", action="store_true", help="turn off field-history tracking on the Opportunity fields")
    ap.add_argument("--allow-placeholders", action="store_true",
                    help="build even if values are still empty/placeholders (fill them in Setup before go-live)")
    ap.add_argument("--out", default=str(ROOT / "build" / "prod"))
    a = ap.parse_args()
    global ALLOW_PLACEHOLDERS
    ALLOW_PLACEHOLDERS = a.allow_placeholders
    if not a.org_svs and not a.skip_svs:
        die("give --org-svs <retrieved folder> (first install / value-set change) or --skip-svs")
    if a.first_install and not a.values:
        die("--first-install needs --values: production has no Cardcom_Setting.Default yet")

    out = pathlib.Path(a.out)
    shutil.rmtree(out, ignore_errors=True)
    out_default = out / "force-app" / "main" / "default"
    shutil.copytree(SRC, out_default)
    shutil.copy(ROOT / "sfdx-project.json", out)
    shutil.copy(ROOT / ".forceignore", out)
    print(f"Building {out}")

    if a.skip_svs:
        shutil.rmtree(out_default / "standardValueSets")
        shutil.rmtree(out_default / "standardValueSetTranslations")
        print("  standard value sets: LEFT OUT (--skip-svs)")
    else:
        merge_svs(out_default, a.org_svs, a.first_install)
    fill_settings(out_default, a.values)
    if not a.first_install:
        (out_default / "customMetadata" / "Donor_Link_Setting.Default.md-meta.xml").unlink()
        print("  Donor_Link_Setting.Default: LEFT OUT (keeps the production secret)")
    else:
        print("  Donor_Link_Setting.Default: included with an EMPTY secret — set it in Setup right after the deploy")
    if not a.with_record_type:
        strip_record_type(out_default)
    if a.no_translations:
        for d in ("objectTranslations", "translations", "standardValueSetTranslations"):
            shutil.rmtree(out_default / d, ignore_errors=True)
        print("  translations: LEFT OUT")
    if a.no_history:
        for f in (out_default / "objects" / "Opportunity" / "fields").glob("*.field-meta.xml"):
            f.write_text(f.read_text(encoding="utf-8").replace("<trackHistory>true</trackHistory>",
                                                               "<trackHistory>false</trackHistory>"), encoding="utf-8")
        print("  Opportunity field history: OFF")

    left = [str(p.relative_to(out)) for p in out_default.rglob("*.xml")
            if any(s in p.read_text(encoding="utf-8", errors="ignore") for s in PLACEHOLDERS)]
    if left:
        print("  WARNING placeholders remain in: " + ", ".join(left))

    make_cmdt_public(out_default)
    write_phase1(out, out_default)

    tests = sorted(p.stem for p in (out_default / "classes").glob("*Test.cls"))
    (out / "tests.txt").write_text("\n".join(tests) + "\n", encoding="utf-8")
    print(f"  {len(tests)} test classes -> {out / 'tests.txt'}")

    sf = shutil.which("sf")
    if sf:
        subprocess.run([sf, "project", "generate", "manifest", "--source-dir", "force-app", "--output-dir", "manifest"], cwd=out, check=True, stdout=subprocess.DEVNULL)
        print(f"  manifest -> {out / 'manifest' / 'package.xml'}")
    else:
        print("  sf CLI not found: manifest not generated (the deploy script uses --source-dir anyway)")
    print("Done. Next: deploy-prod <alias> phase1 (first install), then deploy-prod <alias> validate")


if __name__ == "__main__":
    main()
