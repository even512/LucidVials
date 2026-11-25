// Zaehlt je Lua-Funktion die Upvalues (Locals aus umschliessenden Funktionen, auch ueber verschachtelte Funktionen
// durchgereicht) - wie der Lua-5.1-Compiler. Lua 5.1 erlaubt hoechstens 60 (LUAI_MAXUPVALUES); darueber laedt die ganze
// Datei im Client nicht ("function at line N has more than 60 upvalues"). Die Test-VM (fengari, Lua 5.3: 255) merkt das nicht.
// Aufruf: countUpvalues(quelltext) -> [{ line, count, names }] je Funktion (der Hauptchunk hat keine Upvalues).

import luaparse from "luaparse";

export const UPVALUE_LIMIT = 60; // Lua 5.1
export const UPVALUE_WARN = 50;

export function countUpvalues(code) {
  const ast = luaparse.parse(code, { luaVersion: "5.1", locations: true });
  const results = [];
  // scopes: { names: Map(name -> decl), fn } ; fns: Stapel offener Funktionen { up: Map(decl -> name), line }
  const scopes = [];
  const fns = [];
  let declId = 0;

  const declare = (name) => {
    scopes[scopes.length - 1].names.set(name, { id: ++declId, fn: fns.length });
  };
  const ref = (name) => {
    for (let i = scopes.length - 1; i >= 0; i--) {
      const d = scopes[i].names.get(name);
      if (d) {
        // Upvalue fuer jede Funktion zwischen der Deklaration und der aktuellen (Lua reicht es durch)
        for (let f = d.fn; f < fns.length; f++) fns[f].up.set(d.id, name);
        return;
      }
    }
  };
  const pushScope = () => scopes.push({ names: new Map() });
  const popScope = () => scopes.pop();

  const visitAll = (list) => { for (const n of list || []) visit(n); };
  const block = (body, pre) => {
    pushScope();
    if (pre) pre();
    visitAll(body);
    popScope();
  };
  const fnBody = (node, selfName) => {
    fns.push({ up: new Map(), line: node.loc ? node.loc.start.line : 0 });
    pushScope();
    if (selfName) declare("self");
    for (const p of node.parameters || []) if (p.type === "Identifier") declare(p.name);
    visitAll(node.body);
    popScope();
    const f = fns.pop();
    results.push({ line: f.line, count: f.up.size, names: [...new Set(f.up.values())] });
  };

  function visit(n) {
    if (!n || typeof n !== "object") return;
    switch (n.type) {
      case "Identifier": ref(n.name); return;
      case "LocalStatement":
        visitAll(n.init);
        for (const v of n.variables) declare(v.name);
        return;
      case "FunctionDeclaration":
        if (n.isLocal && n.identifier) {
          declare(n.identifier.name); // local function f: f ist im Rumpf sichtbar
          fnBody(n, false);
        } else {
          if (n.identifier) visit(n.identifier);
          const isMethod = n.identifier && n.identifier.type === "MemberExpression" && n.identifier.indexer === ":";
          fnBody(n, isMethod);
        }
        return;
      case "MemberExpression": visit(n.base); return;
      case "TableKeyString": visit(n.value); return;
      case "TableKey": visit(n.key); visit(n.value); return;
      case "DoStatement": block(n.body); return;
      case "WhileStatement": visit(n.condition); block(n.body); return;
      case "RepeatStatement":
        pushScope(); visitAll(n.body); visit(n.condition); popScope(); return;
      case "IfStatement":
        for (const c of n.clauses) { visit(c.condition); block(c.body); }
        return;
      case "ForNumericStatement":
        visit(n.start); visit(n.end); visit(n.step);
        block(n.body, () => declare(n.variable.name));
        return;
      case "ForGenericStatement":
        visitAll(n.iterators);
        block(n.body, () => { for (const v of n.variables) declare(v.name); });
        return;
      case "LabelStatement": case "GotoStatement": return;
      default:
        for (const [k, v] of Object.entries(n)) {
          if (k === "loc" || k === "range") continue;
          if (Array.isArray(v)) visitAll(v);
          else if (v && typeof v === "object" && v.type) visit(v);
        }
    }
  }

  pushScope();
  fns.push({ up: new Map(), line: 0 }); // Hauptchunk
  visitAll(ast.body);
  return results;
}
