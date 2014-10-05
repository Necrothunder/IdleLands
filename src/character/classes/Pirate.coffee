
Class = require "./../base/Class"
RestrictedNumber = require "restricted-number"

class Pirate extends Class

  baseHp: 150
  baseHpPerLevel: 15
  baseHpPerCon: 10

  baseMp: 10
  baseMpPerLevel: 3
  baseMpPerInt: 5

  baseConPerLevel: 3
  baseDexPerLevel: 2
  baseAgiPerLevel: 2
  baseStrPerLevel: 2
  baseIntPerLevel: 1
  baseWisPerLevel: 1

  itemScore: (player, item) ->
    item.con*2 +
    item.agi*1.5 +
    item.dex*1.5 +
    item.luck*1.1 + 
    item.str +
    item.int*0.7 +
    item.wis*0.7

  physicalAttackChance: -> -10

  minDamage: (player) ->
    player.calc.damage()*0.15

  baseXpGainPerCombat: 80 # Default: 100
  baseXpGainPerOpponentLevel: 40 # Default: 50

  baseGoldGainPerCombat: 20 # 20% of exp
  baseGoldGainPerOpponentLevel: 10 # 20% of exp

  drunkPct = new RestrictedNumber 0, 100, 0

  constructor: -> @drunkPct = new RestrictedNumber 0, 100, 0

  events: {}

  load: (player) ->
    super player
    player.special.maximum = 99
    player.special.name = "Bottles"
    player.on "combat.battle.start", @events.battleStart = -> 
      player.special.toMaximum()
      player.profession.drunkPct.toMinimum()

  unload: (player) ->
    player.special.maximum = 0
    player.special.name = ""
    player.off "combat.battle.start", @events.battleStart
    player.baseGoldGainPerCombat = 0
    player.baseGoldGainPerOpponentLevel = 0

module.exports = exports = Pirate