#!/usr/bin/env python3
"""Adds the donation parts to a Contact page layout retrieved from the target org (README 19, N107).

It keeps everything already in the layout and only adds what is missing:
  * a "Micro Donor" section with Donor_Source__c, Needs_Review__c, Review_Reason__c and the org's Israeli_Id__c
    (each only if the layout doesn't show it yet; never the encrypted Donor_Tax_Id__c, N106);
  * related lists Daily Donation Pledges (Opportunity.Donor_Contact__c) and Monthly Receipts (Monthly_Receipt__c.Contact__c);
  * the action "Create Monthly Receipt" (Contact.Plan_Monthly_Receipt) in the Lightning actions (platformActionList) when the
    layout already overrides them; otherwise it says to add it in Setup (a flow action can't go into quickActionList).
Deploying the org's own layout back with these additions changes nothing else in it.

Usage:
  sf project retrieve start --target-org prod --metadata "Layout:Contact-Contact Layout" --output-dir build/prod-layouts
  python scripts/prod/patch-contact-layout.py build/prod-layouts
  then the deploy command the script prints (a deploy without Apex: no tests run)
"""
import pathlib
import re
import sys

SECTION_FIELDS = ["Donor_Source__c", "Needs_Review__c", "Review_Reason__c", "Israeli_Id__c"]
RELATED = ["Opportunity.Donor_Contact__c", "Monthly_Receipt__c.Contact__c"]
ACTION = "Contact.Plan_Monthly_Receipt"
# Layout elements that come after the ones we insert (Metadata API order)
AFTER_SECTIONS = ["miniLayout", "multilineLayoutFields", "platformActionList", "quickActionList", "relatedContent",
                  "relatedLists", "relatedObjects", "runAssignmentRulesDefault", "showEmailCheckbox", "showHighlightsPanel",
                  "showInteractionLogPanel", "showKnowledgeComponent", "showRunAssignmentRulesCheckbox",
                  "showSolutionSection", "showSubmitAndAttachButton", "summaryLayout"]


def insert_before_first(xml, tags, block):
    """Insert block before the first top-level element whose tag is in tags (else before </Layout>)."""
    best = None
    for t in tags:
        m = re.search(r"\n[ \t]*<" + t + r"[ >]", xml)
        if m and (best is None or m.start() < best):
            best = m.start()
    pos = best if best is not None else xml.rfind("\n</Layout>")
    return xml[:pos] + "\n" + block.rstrip("\n") + xml[pos:]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = pathlib.Path(sys.argv[1])
    if path.is_dir():
        hits = sorted(path.rglob("Contact-*.layout-meta.xml"))
        if len(hits) != 1:
            sys.exit(f"expected one Contact layout under {path}, found {[str(h) for h in hits]}")
        path = hits[0]
    xml = path.read_text(encoding="utf-8")
    present = set(re.findall(r"<field>([^<]+)</field>", xml))
    added = []

    fields = [f for f in SECTION_FIELDS if f not in present]
    if "<label>Micro Donor</label>" not in xml and fields:
        items = "".join(f"""            <layoutItems>
                <behavior>Edit</behavior>
                <field>{f}</field>
            </layoutItems>
""" for f in fields)
        section = f"""    <layoutSections>
        <customLabel>true</customLabel>
        <detailHeading>true</detailHeading>
        <editHeading>true</editHeading>
        <label>Micro Donor</label>
        <layoutColumns>
{items}        </layoutColumns>
        <layoutColumns/>
        <style>TwoColumnsLeftToRight</style>
    </layoutSections>
"""
        m = re.search(r"\n[ \t]*<layoutSections>", xml)
        xml = (xml[:m.start()] + "\n" + section.rstrip("\n") + xml[m.start():]) if m \
            else insert_before_first(xml, AFTER_SECTIONS, section)
        added.append("section Micro Donor: " + ", ".join(fields))

    rel_blocks = ""
    for r in RELATED:
        if f"<relatedList>{r}</relatedList>" not in xml:
            rel_blocks += f"""    <relatedLists>
        <relatedList>{r}</relatedList>
    </relatedLists>
"""
            added.append("related list " + r)
    if rel_blocks:
        last = xml.rfind("</relatedLists>")
        if last >= 0:
            cut = last + len("</relatedLists>")
            xml = xml[:cut] + "\n" + rel_blocks.rstrip("\n") + xml[cut:]
        else:
            xml = insert_before_first(xml, AFTER_SECTIONS[AFTER_SECTIONS.index("relatedObjects"):], rel_blocks)

    # A flow quick action can't go into quickActionList (classic publisher): Lightning actions live in platformActionList.
    # Undo an earlier version of this script that put it in quickActionList.
    xml = re.sub(r"[ \t]*<quickActionListItems>\s*<quickActionName>" + re.escape(ACTION) +
                 r"</quickActionName>\s*</quickActionListItems>\n?", "", xml)
    manual = False
    if f"<actionName>{ACTION}</actionName>" not in xml:
        if "</platformActionList>" in xml:
            orders = [int(x) for x in re.findall(r"<sortOrder>(\d+)</sortOrder>", xml.split("<platformActionList>")[1].split("</platformActionList>")[0])]
            item = f"""        <platformActionListItems>
            <actionName>{ACTION}</actionName>
            <actionType>QuickAction</actionType>
            <sortOrder>{(max(orders) + 1) if orders else 0}</sortOrder>
        </platformActionListItems>
"""
            xml = xml.replace("    </platformActionList>", item + "    </platformActionList>", 1)
            added.append("action " + ACTION + " (Lightning actions)")
        else:
            manual = True   # the layout uses Salesforce's predefined actions; overriding them by file would drop them

    path.write_text(xml, encoding="utf-8")
    root = path.parent.parent
    (root / "sfdx-project.json").write_text(
        '{"packageDirectories":[{"path":"layouts","default":true}],"sourceApiVersion":"62.0"}\n', encoding="utf-8")
    print(f"  file: {path}")
    print("\n".join("  added " + a for a in added) if added else "  nothing to add (already there)")
    if manual:
        print("  NOT added: the action 'Create Monthly Receipt'. This layout uses Salesforce's predefined Lightning actions.")
        print("  Add it in Setup: Contact > Page Layouts > the layout > Mobile & Lightning Actions > click the wrench to override,")
        print("  drag 'Create Monthly Receipt' into 'Salesforce Mobile and Lightning Experience Actions', Save.")
    if not added:
        print("Nothing to deploy.")
        return
    print("Deploy (org change, layout only):")
    print(f'  cd "{root}" && sf project deploy start --target-org prod --source-dir layouts')


if __name__ == "__main__":
    main()
