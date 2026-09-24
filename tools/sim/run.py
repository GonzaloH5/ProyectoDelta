#!/usr/bin/env python3
"""Ejecuta código del juego fuera de Roblox Studio con una imitación mínima de Roblox.

Empaqueta en un solo programa Luau: roblox.luau + physics.luau + los ModuleScript de src/ (con sus rutas de
instancia según default.project.json) + un script "driver" de drivers/. Luego lo ejecuta con el CLI de Luau.

Uso:
  python3 tools/sim/run.py drivers/check.luau [clave=valor ...]
  LUAU=/ruta/a/luau python3 tools/sim/run.py drivers/layout.luau

Los pares clave=valor llegan al driver en la tabla ARGS (números convertidos). Necesita el ejecutable `luau`
(https://github.com/luau-lang/luau/releases) en el PATH o en la variable LUAU.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))


def modules_from_project():
    """Devuelve [(ruta de instancia, archivo)] de los ModuleScript mapeados por default.project.json."""
    with open(os.path.join(ROOT, "default.project.json"), encoding="utf-8") as f:
        project = json.load(f)
    result = []

    def walk(node, path):
        for key, value in node.items():
            if key.startswith("$"):
                continue
            child_path = path + [key]
            if isinstance(value, dict):
                if "$path" in value:
                    collect(os.path.join(ROOT, value["$path"]), child_path)
                walk(value, child_path)

    def collect(folder, path):
        if not os.path.isdir(folder):
            return
        for name in sorted(os.listdir(folder)):
            full = os.path.join(folder, name)
            if os.path.isdir(full):
                collect(full, path + [name])
            elif name.endswith(".luau") or name.endswith(".lua"):
                base = name.rsplit(".", 1)[0]
                if base.endswith(".server") or base.endswith(".client") or base.startswith("init"):
                    continue  # scripts: no se pueden requerir
                result.append((path + [base], full))

    walk(project["tree"], [])
    return result


def lua_string(text):
    return json.dumps(text, ensure_ascii=False)


def lua_value(raw):
    try:
        float(raw)
        return raw
    except ValueError:
        if raw in ("true", "false", "nil"):
            return raw
        return lua_string(raw)


def build(driver, args):
    parts = []
    with open(os.path.join(HERE, "roblox.luau"), encoding="utf-8") as f:
        parts.append(f.read())
    with open(os.path.join(HERE, "physics.luau"), encoding="utf-8") as f:
        parts.append(f.read())
    parts.append(
        "local typeof, Vector3, CFrame, Color3, UDim, UDim2, Vector2, ColorSequence, NumberSequence, Enum, Random, Instance, RaycastParams, OverlapParams, game, workspace, task, warn =\n"
        "\tRoblox.typeof, Roblox.Vector3, Roblox.CFrame, Roblox.Color3, Roblox.UDim, Roblox.UDim2, Roblox.Vector2, Roblox.ColorSequence, Roblox.NumberSequence, Roblox.Enum, Roblox.Random, Roblox.Instance,\n"
        "\tRoblox.RaycastParams, Roblox.OverlapParams, Roblox.game, Roblox.workspace, Roblox.task, Roblox.warn\n"
        "local realClock = os.clock\n"
        "local os = setmetatable({ clock = function() return Roblox.sim.now end }, { __index = os }) -- reloj simulado\n"
        "local require\n"
        "local __loaders = {}\n"
    )
    registered = []
    fine = "fine=true" in args
    for path, file in modules_from_project():
        key = "/".join(path)
        with open(file, encoding="utf-8") as f:
            source = f.read()
        if fine and key.endswith("DevTools/FlightTester"):
            # Márgenes finos para ver la holgura real (la regla sigue igual: 4 y 8 están en la lista).
            old = "local MARGINS = { 32, 24, 16, 8, 4 }"
            if old not in source:
                raise SystemExit("fine=true: no encuentro la lista MARGINS en FlightTester")
            source = source.replace(old, "local MARGINS = { 32, 28, 24, 20, 16, 14, 12, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1 }")
        parts.append(f"__loaders[{lua_string(key)}] = function(script)\n{source}\nend\n")
        registered.append(key)
    parts.append(
        """
do
	local cache = {}
	local function ensure(path)
		local node = game
		for i, name in path do
			local child = node:FindFirstChild(name)
			if not child then
				if i == 1 then
					child = game:GetService(name)
				else
					child = Instance.new(if i == #path then "ModuleScript" else "Folder")
					child.Name = name
					child.Parent = node
				end
			end
			node = child
		end
		return node
	end
	for _, key in { %s } do
		local module = ensure(string.split(key, "/"))
		module._module = key
	end
	require = function(target)
		if type(target) == "table" and target._module then
			if cache[target] == nil then
				cache[target] = __loaders[target._module](target)
			end
			return cache[target]
		end
		error("require: se esperaba un ModuleScript, llegó " .. tostring(target), 2)
	end
end
"""
        % ", ".join(lua_string(k) for k in registered)
    )
    arg_items = []
    for item in args:
        if "=" not in item:
            raise SystemExit(f"argumento sin '=': {item}")
        k, v = item.split("=", 1)
        arg_items.append(f"[{lua_string(k)}] = {lua_value(v)}")
    parts.append("local ARGS = { " + ", ".join(arg_items) + " }\n")
    driver_path = driver if os.path.isabs(driver) else os.path.join(HERE, driver)
    with open(driver_path, encoding="utf-8") as f:
        parts.append("do\n" + f.read() + "\nend\n")
    return "\n".join(parts)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    driver, args = sys.argv[1], sys.argv[2:]
    program = build(driver, args)
    luau = os.environ.get("LUAU") or shutil.which("luau")
    if not luau:
        raise SystemExit("No encuentro el ejecutable luau (ponlo en el PATH o en la variable LUAU)")
    keep = os.environ.get("SIM_KEEP")
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as tmp:
        tmp.write(program)
        path = tmp.name
    try:
        return subprocess.call([luau, "-O2", "--codegen", path])
    finally:
        if keep:
            shutil.copy(path, keep)
        os.unlink(path)


if __name__ == "__main__":
    sys.exit(main())
