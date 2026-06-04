import json
import os
import sys

def main():
    graph_path = os.path.join(r"c:\Users\Aniket\Desktop\enterprise_auth_system", "graphify-out", "graph.json")
    try:
        with open(graph_path, 'r', encoding='utf-8') as f:
            d = json.load(f)
    except Exception as e:
        print(f"Error loading graph.json: {e}")
        return

    components = [n for n in d.get('nodes', []) if n.get('label') == 'COMPONENT']
    print(f"Found {len(components)} COMPONENT nodes.")
    print(json.dumps(components[:5], indent=2))

if __name__ == '__main__':
    main()
