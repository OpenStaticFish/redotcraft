# Survival Crafting Progression

Survival starts with an empty inventory. Crafting uses recipe buttons rather than
a shaped ingredient grid. Open the inventory with **E**, scroll to the recipe
book, and search by an output or ingredient name. Categories and **Craftable only**
help narrow the list. Requirements show **owned / needed** quantities.

**Craft 1** makes one batch, not necessarily one item. **Craft Max** makes up to
64 batches that fit the backpack. Failed crafts consume nothing. A larger batch
can sometimes fit when a single batch cannot, because it empties an ingredient
slot. Table recipes require opening a placed crafting table, not merely carrying
one.

## 1. Logs to Wooden Tools

Oak, spruce, birch, acacia, jungle, and mangrove logs all work. Each has a recipe
producing the same placeable **Wooden Planks** block; mixed species therefore do
not strand incompatible crafting materials.

| Recipe | Ingredients | Output | Where |
|---|---|---|---|
| Wooden planks | 1 log of any species | 4 planks | Inventory |
| Sticks | 2 planks | 4 sticks | Inventory |
| Bamboo sticks | 2 bamboo | 1 stick | Inventory |
| Crafting table | 4 planks | 1 table | Inventory |
| Wooden pickaxe | 3 planks + 2 sticks | 1 tool | Table |
| Wooden axe | 3 planks + 2 sticks | 1 tool | Table |
| Wooden shovel | 1 plank + 2 sticks | 1 tool | Table |

**First milestone: harvest three logs by hand.** Craft them into 12 planks, then
make a table and one batch of sticks. Move the table to a hotbar slot, place it,
and right-click it. Craft a wooden pickaxe. You still have three planks and two
sticks left over. Axes speed up wood harvesting; they are not needed to start.

## 2. Stone, Storage, and a Furnace

Mine ordinary stone with the wooden pickaxe. It drops **cobblestone**, not smooth
stone. Breaking it with an unsuitable tool does not award a block. Mining wears
the tool only when a block actually breaks.

| Recipe | Ingredients | Output | Where |
|---|---|---|---|
| Stone pickaxe or axe | 3 cobblestone + 2 sticks | 1 tool | Table |
| Stone shovel | 1 cobblestone + 2 sticks | 1 tool | Table |
| Furnace | 8 cobblestone | 1 furnace | Table |
| Chest | 8 planks | 1 chest, 27 slots | Table |
| Crushed deepstone | 1 deepstone | 1 cobblestone | Inventory |

**Second milestone: mine 11 stone blocks** for a stone pickaxe and furnace.
Keep gathering wood for replacement tools, fuel, storage, and shelter.

## 3. Fuel and Light Without Finding Coal

Place and open the furnace. Move material into **Input**, combustible material
into **Fuel**, and collect the **Output**. Output slots cannot accept items.
Furnaces run while playing; close the inventory to let time advance. Every item
takes ten seconds. Partial progress and remaining fuel survive saving/loading.

| Fuel | Burn Time | Smelts per Fresh Fuel Item |
|---|---|---|
| Coal or charcoal | 80 seconds | 8 |
| Any log, plank, or wooden tool | 15 seconds | 1.5 |
| Stick | 5 seconds | 0.5 |

Smelt a log of **any species** into charcoal using another log or planks as fuel.
One coal **or** charcoal plus one stick makes **four torches** in the inventory.
Wooden pickaxes can also harvest coal ore, which drops coal directly.

Fuel time is shared across successive smelts. An already-lit furnace can burn
remaining fuel while idle, so load the next input before leaving it running.

## 4. Iron and Further Materials

Use a **stone pickaxe** to harvest iron ore, then smelt it into iron ingots.
At the crafting table, iron pickaxes/axes cost three ingots and two sticks;
an iron shovel costs one ingot and two sticks. Iron pickaxes can harvest gold ore.
Gold can be smelted and stored, but gold equipment is not implemented.

| Smelting Input | Output |
|---|---|
| Iron ore | Iron ingot |
| Gold ore | Gold ingot |
| Any log | Charcoal |
| Sand or red sand | Glass |
| Cobblestone | Smooth stone |
| Clay | Terracotta |
| Kelp | Dried kelp |

Knap one gravel into one flint in the inventory. One flint and one iron ingot
make flint-and-steel at a table. These recipes do not rely on random gravel drops.

## 5. Foraged Food

| Recipe | Ingredients | Output / Use |
|---|---|---|
| Melon slices | 1 melon block | 4 slices; each restores 2 hunger |
| Melon block | 4 slices | 1 placeable melon; no net item gain |
| Bowls | 3 planks | 4 bowls |
| Mushroom stew | 1 bowl + 1 brown mushroom + 1 red mushroom | Restores 6 hunger; returns the bowl |
| Dried kelp | Smelt 1 kelp | Restores 1 hunger |

These crafting recipes work in the inventory without a table. Select prepared
food and right-click to eat. Whole melons are building blocks, not directly
edible items. Eating at full hunger consumes nothing. A returned bowl goes into
the backpack, or becomes a physical drop if there is no room.

Foraging is **not renewable farming**: local melons, mushrooms, and kelp do not
regrow yet. Meat items exist in Creative, but Survival has no animal source.
Farming, renewable food, animals, and further equipment are future work.

## World and Save Rules

- Normal and Amplified worlds support the ore progression above.
- New worldgen version 14 generates ores even when cave density is zero.
- Existing version 13 and older worlds retain their generation behavior;
  changing recipes does not regenerate their terrain.
- Flat worlds have no generated trees or ores and are resource-limited.
  The creation form warns about this when selecting Flat Survival.
- Existing block and item IDs are unchanged. New content is appended, so stored
  logs, tools, inventories, and containers remain usable.
- Creative still has the free catalog and unlimited building. These recipes do
  not provide a way to change a world's game mode.

## Regression Coverage

`tools/survival_progression_verify.gd` repeats the complete path for all six log
species from empty inventory through iron tools and gold harvesting. It uses
timed Player mining, Main's drop/tool-wear handling, physical pickup, placed
stations, UI crafting, and mid-smelt save restoration. It also checks table
gates, incorrect-tool harvesting, prepared foods, and full-inventory bowl returns.

Model atomicity, recipe filtering, keyboard crafting, and capacity behavior are
covered by `inventory_crafting_verify.gd` and `inventory_ui_verify.gd`.
