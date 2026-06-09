import json
import re
from collections import Counter
from pathlib import Path

def analyze_communities():
    base_dir = Path(r"c:\Users\Aniket\Desktop\enterprise_auth_system\graphify-out")
    analysis_path = base_dir / ".graphify_analysis.json"
    labels_path = base_dir / ".graphify_labels.json"
    report_path = base_dir / "community_analysis.md"

    if not analysis_path.exists():
        print(f"Error: {analysis_path} not found.")
        return

    with open(analysis_path, 'r', encoding='utf-8') as f:
        analysis = json.load(f)

    communities = analysis.get("communities", {})
    labels = {}
    markdown_lines = ["# Community Analysis", ""]

    stop_words = {"dart", "cs", "py", "helper", "controller", "repository", "models", 
                  "services", "ui", "local", "static", "screen", "widgets", "dto", "entities"}

    for cid, nodes in communities.items():
        if not nodes:
            labels[cid] = f"Empty Community {cid}"
            continue

        words = []
        for node in nodes:
            parts = re.split(r'_+', node)
            for part in parts:
                p = part.lower()
                if p and p not in stop_words and not p.isnumeric():
                    words.append(part.capitalize())

        counter = Counter(words)
        common = [w for w, c in counter.most_common(3)]
        
        if common:
            label = " ".join(common) + " Module"
            description = f"Handles operations related to {', '.join(common)}."
        else:
            label = f"Core Component {cid}"
            description = "Miscellaneous core functions."

        labels[cid] = label
        
        markdown_lines.append(f"### {label} (Community {cid})")
        markdown_lines.append(f"**Description:** {description}")
        markdown_lines.append(f"**Nodes ({len(nodes)}):** {', '.join(nodes[:5])}{'...' if len(nodes) > 5 else ''}")
        markdown_lines.append("")

    with open(labels_path, 'w', encoding='utf-8') as f:
        json.dump(labels, f, ensure_ascii=False, indent=2)

    with open(report_path, 'w', encoding='utf-8') as f:
        f.write("\n".join(markdown_lines))

    print(f"Successfully processed {len(communities)} communities.")
    print(f"Updated {labels_path}")
    print(f"Generated {report_path}")

if __name__ == "__main__":
    analyze_communities()
