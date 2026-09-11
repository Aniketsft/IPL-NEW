import json
from pathlib import Path

p = Path("graphify-out/graph.json")
if not p.exists():
    print("No graph.json found")
    exit(0)

data = json.loads(p.read_text(encoding="utf-8"))
nodes = data.get("nodes", [])
links = data.get("links", [])

print(f"Total nodes: {len(nodes)}, Total links: {len(links)}")

terms = ["credit", "invoice", "transaction", "ordersummary", "order_summary", "cancelinvoice"]

matching_nodes = []
for n in nodes:
    label = str(n.get("label", "")).lower()
    source = str(n.get("source_location", "")).lower()
    if any(t in label or t in source for t in terms):
        matching_nodes.append(n)

print(f"Found {len(matching_nodes)} relevant nodes.")
for n in matching_nodes[:20]:
    print(f"- {n.get('id')}: {n.get('label')} [{n.get('source_location', '')}]")
