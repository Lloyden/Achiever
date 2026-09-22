#!/usr/bin/env python3
"""Generate Achiever_data.lua from the realm's CMaNGOS world database.

Run this from the directory containing docker-compose.yml, then copy the
generated faction addon directory into Interface/AddOns on the game client.
No Python packages are required.
"""

from __future__ import annotations

import argparse
import base64
import subprocess
import sys
from pathlib import Path


LOCALE_COLUMNS = {
    "enUS": ("Name_Lang_enUS", "Title_Lang_enUS", "Description_Lang_enUS", "Reward_Lang_enUS"),
    "enGB": ("Name_Lang_enGB", "Title_Lang_enGB", "Description_Lang_enGB", "Reward_Lang_enGB"),
    "deDE": ("Name_Lang_deDE", "Title_Lang_deDE", "Description_Lang_deDE", "Reward_Lang_deDE"),
    "frFR": ("Name_Lang_frFR", "Title_Lang_frFR", "Description_Lang_frFR", "Reward_Lang_frFR"),
    "esES": ("Name_Lang_esES", "Title_Lang_esES", "Description_Lang_esES", "Reward_Lang_esES"),
    "esMX": ("Name_Lang_esMX", "Title_Lang_esMX", "Description_Lang_esMX", "Reward_Lang_esMX"),
    "ruRU": ("Name_Lang_ruRU", "Title_Lang_ruRU", "Description_Lang_ruRU", "Reward_Lang_ruRU"),
}


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--service", default="db", help="Docker Compose database service (default: db)")
    parser.add_argument("--database", default="classicmangos", help="World database (default: classicmangos)")
    parser.add_argument("--faction", choices=("Alliance", "Horde"), default="Alliance")
    parser.add_argument("--locale", choices=sorted(LOCALE_COLUMNS), default="enUS")
    parser.add_argument("--patch", type=int, default=0, help="Realm patch number (Classic default: 0)")
    parser.add_argument("--output", type=Path, default=None,
                        help="Output Lua file (default: Achiever_Data_<Faction>/Achiever_data.lua)")
    return parser.parse_args()


def query(service: str, database: str, sql: str) -> list[list[str]]:
    # Expansion happens inside the container. The password therefore never
    # appears in the host's command line or this script's output.
    command = [
        "docker", "compose", "exec", "-T", service, "sh", "-lc",
        'db_password="${MARIADB_ROOT_PASSWORD:-$MYSQL_ROOT_PASSWORD}"; '
        'db_client="$(command -v mariadb || command -v mysql)"; '
        'test -n "$db_client" || { echo "mariadb/mysql client missing" >&2; exit 127; }; '
        'exec "$db_client" -uroot -p"$db_password" --batch --skip-column-names "$1"',
        "achiever-db", database,
    ]
    try:
        result = subprocess.run(command, input=sql, text=True, capture_output=True, check=False)
    except FileNotFoundError:
        raise SystemExit("Fel: docker hittades inte. Kör skriptet på servern där Docker Compose finns.")
    if result.returncode:
        details = result.stderr.strip() or result.stdout.strip() or "okänt databasfel"
        raise SystemExit(f"Fel: databasfrågan misslyckades:\n{details}")
    return [line.split("\t") for line in result.stdout.splitlines() if line]


def b64(column: str, table: str = "") -> str:
    column = column.strip("`")
    prefix = f"{table}." if table else ""
    return f"REPLACE(TO_BASE64(COALESCE({prefix}`{column}`, '')), CHAR(10), '')"


def decode(value: str) -> str:
    if not value or value == "NULL":
        return ""
    return base64.b64decode(value).decode("utf-8")


def lua_string(value: str) -> str:
    escaped = (value.replace("\\", "\\\\").replace('"', '\\"')
               .replace("\r", "\\r").replace("\n", "\\n").replace("\t", "\\t"))
    return f'"{escaped}"'


def integer(value: str) -> int:
    return int(value or 0)


def main() -> int:
    args = arguments()
    category_name, title, description, reward = LOCALE_COLUMNS[args.locale]
    faction_id = 1 if args.faction == "Alliance" else 0
    faction_sql = f"a.`Faction` IN (-1, {faction_id})"

    categories = query(args.service, args.database, f"""
SELECT `ID`, `Parent`, {b64(category_name)}, `Ui_Order`
FROM `achievement_category_dbc`
WHERE `patch` <= {args.patch}
ORDER BY `ID`;
""")
    achievements = query(args.service, args.database, f"""
SELECT a.`ID`, a.`Supercedes`, {b64(title)}, {b64(description)},
       a.`Category`, a.`Points`, a.`Ui_Order`, a.`Flags`, a.`IconID`, {b64(reward)}
FROM `achievement_dbc` a
WHERE a.`patch` <= {args.patch} AND {faction_sql}
ORDER BY a.`ID`;
""")
    criteria = query(args.service, args.database, f"""
SELECT c.`ID`, c.`Achievement_Id`, c.`Type`, c.`Asset_Id`, c.`Quantity`,
       {b64(description, "c")}, c.`Flags`, c.`Ui_Order`
FROM `achievement_criteria_dbc` c
JOIN `achievement_dbc` a ON a.`ID` = c.`Achievement_Id`
WHERE a.`patch` <= {args.patch} AND {faction_sql}
ORDER BY c.`ID`;
""")

    if not categories or not achievements or not criteria:
        raise SystemExit(
            "Fel: minst en metadatatabell gav noll rader. Kontrollera databasnamn, patch och importerad SQL."
        )

    category_data: list[str] = []
    category_index: dict[int, dict[int, int]] = {}
    for row in categories:
        if len(row) != 4:
            raise SystemExit("Fel: oväntat resultat från achievement_category_dbc.")
        ident, parent, name, order = integer(row[0]), integer(row[1]), decode(row[2]), integer(row[3])
        category_data.append(
            f"[{ident}]={{id={ident},parentId={parent},name={lua_string(name)},order={order}}}"
        )
        category_index.setdefault(parent, {})[order] = ident

    achievement_data: list[str] = []
    achievement_index: dict[int, dict[int, int]] = {}
    previous: dict[int, int] = {}
    following: dict[int, int] = {}
    total_points = 0
    for row in achievements:
        if len(row) != 10:
            raise SystemExit("Fel: oväntat resultat från achievement_dbc.")
        ident, supercedes = integer(row[0]), integer(row[1])
        category, points, order = integer(row[4]), integer(row[5]), integer(row[6])
        flags, icon = integer(row[7]), integer(row[8])
        total_points += points
        achievement_data.append(
            f"[{ident}]={{id={ident},name={lua_string(decode(row[2]))},"
            f"description={lua_string(decode(row[3]))},categoryId={category},points={points},"
            f"order={order},flags={flags},icon={icon},titleReward={lua_string(decode(row[9]))}}}"
        )
        achievement_index.setdefault(category, {})[order] = ident
        if supercedes:
            previous[ident] = supercedes
            following[supercedes] = ident

    criterion_data: list[str] = []
    criterion_index: dict[int, dict[int, int]] = {}
    for row in criteria:
        if len(row) != 8:
            raise SystemExit("Fel: oväntat resultat från achievement_criteria_dbc.")
        ident, achievement = integer(row[0]), integer(row[1])
        criterion_type, asset, count = integer(row[2]), integer(row[3]), integer(row[4])
        flags, order = integer(row[6]), integer(row[7])
        criterion_data.append(
            f"[{ident}]={{id={ident},achievementId={achievement},type={criterion_type},"
            f"assetId={asset},count={count},name={lua_string(decode(row[5]))},flags={flags}}}"
        )
        criterion_index.setdefault(achievement, {})[order] = ident

    def flat_index(values: dict[int, dict[int, int]]) -> str:
        groups = []
        for key in sorted(values):
            entries = ",".join(f"[{order}]={ident}" for order, ident in sorted(values[key].items()))
            groups.append(f"[{key}]={{{entries}}}")
        return ",".join(groups)

    def flat_map(values: dict[int, int]) -> str:
        return ",".join(f"[{key}]={values[key]}" for key in sorted(values))

    lua = "\n".join([
        f"-- Generated from {args.database}; patch {args.patch}; {args.faction}; {args.locale}.",
        "-- Do not edit manually; regenerate this file after achievement database changes.",
        "ACHIEVER_EMBEDDED_DB = {",
        f"Alliance={'true' if args.faction == 'Alliance' else 'false'},Horde={'true' if args.faction == 'Horde' else 'false'},",
        "sync={complete=true,version=1,embedded=true},",
        "categories={version=1,data={" + ",\n".join(category_data) + "},byParent={" + flat_index(category_index) + "}},",
        f"achievements={{version=1,totalPoints={total_points},data={{" + ",\n".join(achievement_data) +
        "},byCategory={" + flat_index(achievement_index) + "},nextById={" + flat_map(following) +
        "},previousById={" + flat_map(previous) + "}},",
        "criteria={version=1,data={" + ",\n".join(criterion_data) + "},byAchievement={" +
        flat_index(criterion_index) + "}}",
        "}",
        "",
    ])

    output = args.output or Path(f"Achiever_Data_{args.faction}") / "Achiever_data.lua"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(lua, encoding="utf-8", newline="\n")
    print(f"Klart: {output}")
    print(f"  kategorier:   {len(categories)}")
    print(f"  achievements: {len(achievements)}")
    print(f"  criteria:     {len(criteria)}")
    print(f"  faction:      {args.faction}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
