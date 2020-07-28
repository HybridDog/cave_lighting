# cave_lighting API

This mod currently exposes only a few functions.
See also the explanation in the main mod description.

* `cave_lighting.light_cave(player, maxlight)`
  lights up a dark area, e.g. a cave, with the player's wield item;
  maxlight specifies the maximum light value for positions in which a light
  source node is placed.
  Returns a success boolean and a message
* `cave_lighting.enable_auto_placing(player_name, maxlight)`
  Enables the automatic light placing for the player,
  or sets the maxlight to a different value
* `cave_lighting.disable_auto_placing(player_name)`
  Disables the automatic light placing for the player
