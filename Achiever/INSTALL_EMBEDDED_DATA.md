# Faction metadata installation

Achiever 0.6.0 keeps Alliance and Horde definitions in separate LoadOnDemand
addons. The Vanilla client therefore parses only the current character's
faction file.

On the CMaNGOS server, from the Compose directory:

```bash
python3 generate_achiever_data.py --faction Alliance
python3 generate_achiever_data.py --faction Horde
```

This creates:

```text
Achiever_Data_Alliance/Achiever_data.lua
Achiever_Data_Horde/Achiever_data.lua
```

Copy each generated Lua file into the same-named addon directory on the game
client under `Interface/AddOns`. Do not put either file in the main `Achiever`
directory.

The data addons must remain enabled in the character-selection addon list.
Their `LoadOnDemand` flag prevents the unused faction file from being read.
