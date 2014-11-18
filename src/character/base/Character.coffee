
RestrictedNumber = require "restricted-number"
EventEmitter2 = require("eventemitter2").EventEmitter2
_ = require "underscore"
Q = require "q"
Personality = require "./Personality"
Constants = require "../../system/Constants"
chance = new (require "chance")()

class Character extends EventEmitter2

  constructor: (options) ->

    [@name, @identifier] = [options.name, options.identifier]
    @hp = new RestrictedNumber 0, 20, 20
    @mp = new RestrictedNumber 0, 0, 0
    @special = new RestrictedNumber 0, 0, 0
    @level = new RestrictedNumber 0, 100, 0
    @equipment = []
    @createDate = new Date()
    @loadCalc()

    @

  moveAction: ->

  combatAction: ->

  clearAffectingSpells: ->
    return if not @spellsAffectedBy

    _.each @spellsAffectedBy, (spell) =>
      spell.suppressed = yes
      spell.unaffect @

    @spellsAffectedBy = []

  probabilityReduce: (appFunctionName, args = [], baseObject) ->
    args = [args] if not _.isArray args
    array = []
    .concat @profession ? []
    .concat @personalities ? []
    .concat @spellsAffectedBy ? []
    .concat @achievements ? []

    baseProbabilities = if baseObject then [baseObject] else []

    probabilities = _.reduce array, (combined, iter) ->
      applied = if _.isFunction iter?[appFunctionName] then iter?[appFunctionName]?.apply iter, args else iter?[appFunctionName]
      combined.push applied if applied?.result.length > 0
      combined
    , baseProbabilities

    return probabilities[0] if probabilities.length < 2

    sortedProbabilities = _.sortBy probabilities, (prob) -> prob.probability
    sum = _.reduce sortedProbabilities, ((prev, prob) -> prev + prob.probability), 0
    sortedProbabilities[i].probability = sortedProbabilities[i].probability + sortedProbabilities[i-1].probability for i in [1...sortedProbabilities.length]
    chosenInt = chance.integer {min: 0, max: sum}
    (_.reject sortedProbabilities, (val) -> val.probability < chosenInt)[0]

  personalityReduce: (appFunctionName, args = [], baseValue = 0) ->
    args = [args] if not _.isArray args
    array = []
    .concat @profession ? []
    .concat @personalities ? []
    .concat @spellsAffectedBy ? []
    .concat @achievements ? []
    .concat @playerManager?.game.calendar.getDateEffects()
    .concat @calendar?.game.calendar.getDateEffects() # for monsters
    .concat @getRegion?()

    _.reduce array, (combined, iter) ->
      applied = if _.isFunction iter?[appFunctionName] then iter?[appFunctionName]?.apply iter, args else iter?[appFunctionName]
      if _.isArray combined
        combined.push applied if applied
      else
        combined += if applied then applied else 0

      combined
    , baseValue

  rebuildPersonalityList: ->
    _.each @personalities, (personality) =>
      personality.unbind? @

    @personalities = _.map @personalityStrings, (personality) =>
      Personality::createPersonality personality, @

  _addPersonality: (newPersonality, potentialPersonality) ->
    if not @personalityStrings
      @personalityStrings = []
      @personalities = []

    @personalityStrings.push newPersonality

    @personalities.push new potentialPersonality @

    @personalities = _.uniq @personalities
    @personalityStrings = _.uniq @personalityStrings

  addPersonality: (newPersonality) ->
    if not Personality::doesPersonalityExist newPersonality
      return Q {isSuccess: no, code: 30, message: "That personality doesn't exist (they're case sensitive)!"}

    potentialPersonality = Personality::getPersonality newPersonality
    if not ('canUse' of potentialPersonality) or not potentialPersonality.canUse @
      return Q {isSuccess: no, code: 31, message: "You can't use that personality yet!"}

    @_addPersonality newPersonality, potentialPersonality

    personalityString = @personalityStrings.join ", "

    Q {isSuccess: yes, code: 33, message: "Your personality settings have been updated successfully! Personalities are now: #{personalityString or "none"}"}

  removePersonality: (oldPersonality) ->
    if not @hasPersonality oldPersonality
      return Q {isSuccess: no, code: 32, message: "You don't have that personality set!"}

    @personalityStrings = _.without @personalityStrings, oldPersonality
    @rebuildPersonalityList()

    personalityString = @personalityStrings.join ", "

    Q {isSuccess: yes, code: 33, message: "Your personality settings have been updated successfully! Personalities are now: #{personalityString or "none"}"}

  hasPersonality: (personality) ->
    return no if not @personalityStrings
    personality in @personalityStrings

  calcGoldGain: (gold) ->
    @calc.stat 'gold', yes, gold

  calcXpGain: (xp) ->
    @calc.stat 'xp', yes, xp

  calcDamageTaken: (baseDamage) ->
    multiplier = @calc.damageMultiplier()
    if baseDamage > 0
      damage = (baseDamage - @calc.damageReduction()) * multiplier
      damage = 0 if damage < 0
      damage
    else baseDamage*multiplier

  canEquip: (item) ->
    current = _.findWhere @equipment, {type: item.type}
    current.score() <= item.score()

  equip: (item) ->
    current = _.findWhere @equipment, {type: item.type}
    @equipment = _.without @equipment, current
    @equipment.push item

  recalculateStats: ->
    @hp.maximum = @calc.hp()
    @mp.maximum = @calc.mp()

    # force a recalculation
    @calc.stats ['str', 'dex', 'con', 'int', 'agi', 'luck', 'wis', 'water', 'fire', 'earth', 'ice', 'thunder']

  levelUpXpCalc: (level) ->
    Math.floor 100 + (400 * Math.pow level, 1.71)

  calcLuckBonusFromValue: (value) ->
    tiers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 15, 25, 35, 50, 65, 75, 85, 100, 125, 150, 175, 200, 225, 250, 300, 350, 400, 450, 500]

    postMaxTierDifference = 100

    bonus = 0

    for i in [0..tiers.length]
      bonus++ if value >= tiers[i]

    if value >= tiers[tiers.length-1]
      bonus++ while value > tiers[tiers.length-1] += postMaxTierDifference

    bonus

  gainXp: ->
  gainGold: ->

  loadCalc: ->
    @calc =
      base: {}
      statCache: {}
      self: @
      stat: (stat, ignoreNegative = yes, base = 0, basePct = 0) ->
        pct = "#{stat}Percent"
        @base[stat] = _.reduce @self.equipment, ((prev, item) -> prev+(item[stat] or 0)), base
        @base[pct] = _.reduce @self.equipment, ((prev, item) -> prev+(item[pct] or 0)), basePct

        @statCache[stat] = baseVal = @self.personalityReduce stat, [@self, @base[stat]], @base[stat]
        @statCache[pct] = percent = @self.personalityReduce pct, [@self, @base[pct]], @base[pct]

        combinedVal = baseVal*(1+percent/100)
        combinedVal = 0 if _.isNaN combinedVal or (not ignoreNegative and combinedVal < 0)
        combinedVal

      stats: (stats) ->
        _.reduce stats, ((prev, stat) => prev+@stat stat), 0

      aegis:    -> 0 < @self.calc.stat 'aegis'
      crit:     -> Math.max 0, @self.calc.stat 'crit'
      dance:    -> 0 < @self.calc.stat 'dance'
      defense:  -> Math.max 0, @self.calc.stat 'defense'
      haste:    -> Math.max 0, @self.calc.stat 'haste'
      prone:    -> 0 < @self.calc.stat 'prone'
      power:    -> 0 < @self.calc.stat 'power'
      offense:  -> Math.max 0, @self.calc.stat 'offense'
      glowing:  -> Math.max 0, @self.calc.stat 'glowing'
      deadeye:  -> Math.max 0, @self.calc.stat 'deadeye'
      silver:   -> 0 < @self.calc.stat 'silver'
      vorpal:   -> 0 < @self.calc.stat 'vorpal'

      boosts: (stats, baseValue) ->
        Math.floor _.reduce stats, (prev, stat) =>
          switch stat
            when 'crit' then                return prev += 100 * @self.calc.crit()
            when 'dance', 'deadeye' then    return prev += baseValue if @self.calc.dance()
            when 'silver', 'power' then     return prev += baseValue / 10 if @self.calc[stat]()
            when 'offense', 'defense' then  return prev += baseValue * @self.calc[stat]()/10
            when 'glowing' then             return prev += baseValue * @self.calc.glowing()/20
            when 'vorpal' then              return prev += baseValue / 2 if @self.calc.vorpal()
          prev
        , 0

      hp: ->
        @base.hp = @self.calc.stat 'hp'
        Math.round Math.max 1, @base.hp

      mp: ->
        @base.mp = @self.calc.stat 'mp'
        Math.round Math.max 0, @base.mp

      dodge: ->
        @base.dodge = @self.calc.stat 'agi'
        value = @self.personalityReduce 'dodge', [@self, @base.dodge], @base.dodge
        value += @self.calc.boosts ['dance', 'glowing', 'defense'], @base.dodge
        value

      beatDodge: ->
        @base.beatDodge = Math.max 10, @self.calc.stats ['dex','str','agi','wis','con','int']
        value = @self.personalityReduce 'beatDodge', [@self, @base.beatDodge], @base.beatDodge
        value += @self.calc.boosts ['deadeye', 'glowing', 'offense'], @base.beatDodge
        value

      hit: ->
        @base.hit = (@self.calc.stats ['dex', 'agi', 'con']) / 6
        value = @self.personalityReduce 'hit', [@self, @base.hit], @base.hit
        value += @self.calc.boosts ['defense', 'glowing'], @base.hit
        value

      beatHit: ->
        @base.beatHit = Math.max 10, (@self.calc.stats ['str', 'dex']) / 2
        value = @self.personalityReduce 'beatHit', [@self, @base.beatHit], @base.beatHit
        value += @self.calc.boosts ['offense', 'glowing'], @base.beatHit
        value

      damage: ->
        @base.damage = Math.max 10, @self.calc.stats ['str']
        value = @self.personalityReduce 'damage', [@self, @base.damage], @base.damage
        value += @self.calc.boosts ['power', 'offense', 'glowing', 'vorpal'], @base.damage
        value

      minDamage: ->
        @base.minDamage = 1
        maxDamage = @self.calc.damage()
        value = @self.personalityReduce 'minDamage', [@self, @base.minDamage], @base.minDamage
        value += @self.calc.boosts ['silver', 'offense', 'glowing', 'vorpal'], maxDamage
        Math.min value, maxDamage-1

      damageReduction: ->
        @base.damageMultiplier = 0
        @self.personalityReduce 'damageReduction', [@self, @base.damageReduction], @base.damageReduction

      damageMultiplier: ->
        @base.damageMultiplier = 1
        @self.personalityReduce 'damageMultiplier', [@self, @base.damageMultiplier], @base.damageMultiplier

      criticalChance: ->
        @base.criticalChance = 1 + ((@self.calc.stats ['luck', 'dex']) / 2)
        value = @self.personalityReduce 'criticalChance', [@self, @base.criticalChance], @base.criticalChance
        value += @self.calc.boosts ['crit'], @base.criticalChance
        value

      physicalAttackChance: ->
        @base.physicalAttackChance = 65
        Math.max 0, Math.min 100, @self.personalityReduce 'physicalAttackChance', [@self, @base.physicalAttackChance], @base.physicalAttackChance

      combatEndXpGain: (oppParty) ->
        @base.combatEndXpGain = 0
        @self.personalityReduce 'combatEndXpGain', [@self, oppParty, @base.combatEndXpGain], @base.combatEndXpGain

      combatEndXpLoss: ->
        @base.combatEndXpLoss = Math.floor self.xp.maximum / 10
        @self.personalityReduce 'combatEndXpLoss', [@self, @base.combatEndXpLoss], @base.combatEndXpLoss

      combatEndGoldGain: (oppParty) ->
        @base.combatEndGoldGain = 0
        @self.personalityReduce 'combatEndGoldGain', [@self, oppParty, @base.combatEndGoldGain], @base.combatEndGoldGain

      combatEndGoldLoss: ->
        @base.combatEndXpLoss = Math.floor self.xp.maximum / 10
        @self.personalityReduce 'combatEndGoldLoss', [@self, @base.combatEndGoldLoss], @base.combatEndGoldLoss

      itemFindRange: ->
        @base.itemFindRange = (@self.level.getValue()+1) * Constants.defaults.player.defaultItemFindModifier * @self.calc.itemFindRangeMultiplier()
        @self.personalityReduce 'itemFindRange', [@self, @base.itemFindRange], @base.itemFindRange

      itemFindRangeMultiplier: ->
        @base.itemFindRangeMultiplier = 1 + (0.2 * Math.floor @self.level.getValue()/10)
        @self.personalityReduce 'itemFindRangeMultiplier', [@self, @base.itemFindRangeMultiplier], @base.itemFindRangeMultiplier

      itemScore: (item) ->
        baseValue = item.score()
        (Math.floor @self.personalityReduce 'itemScore', [@self, item, baseValue], baseValue) + @self.itemPriority item

      totalItemScore: ->
        _.reduce @self.equipment, ((prev, item) -> prev+item.score()), 0

      itemReplaceChancePercent: ->
        @base.itemReplaceChancePercent = 100
        Math.max 0, Math.min 100, @self.personalityReduce 'itemReplaceChancePercent', [@self, @base.itemReplaceChancePercent], @base.itemReplaceChancePercent

      eventFumble: ->
        @base.eventFumble = 25
        @self.personalityReduce 'eventFumble', [@self, @base.eventFumble], @base.eventFumble

      eventModifier: (event) ->
        @base.eventModifier = 0
        @self.personalityReduce 'eventModifier', [@self, event, @base.eventModifier], 0

      skillCrit: (spell) ->
        @base.skillCrit = 1
        @self.personalityReduce 'skillCrit', [@self, spell, @base.skillCrit], @base.skillCrit
        
      itemSellMultiplier: (item) ->
        @base.itemSellMultiplier = 0.05
        @self.personalityReduce 'itemSellMultiplier', [@self, item, @base.itemSellMultiplier], @base.itemSellMultiplier

      damageTaken: (attacker, damage, skillType, spell, reductionType) ->
        baseValue = 0
        @self.personalityReduce 'damageTaken', [@self, attacker, damage, skillType, spell, reductionType], baseValue

      cantAct: ->
        baseValue = 0
        @self.personalityReduce 'cantAct', [@self, baseValue], baseValue

      cantActMessages: ->
        baseValue = []
        @self.personalityReduce 'cantActMessages', [@self, baseValue], baseValue

      luckBonus: ->
        @baseValue = @self.calcLuckBonusFromValue @self.calc.stat 'luck'
        @self.personalityReduce 'luckBonus', [@self, @baseValue], @baseValue

      fleePercent: ->
        @base.fleePercent = 0.1
        Math.max 0, Math.min 100, @self.personalityReduce 'fleePercent', [@self, @base.fleePercent], @base.fleePercent

      partyLeavePercent: ->
        @base.partyLeavePercent = Constants.defaults.player.defaultPartyLeavePercent
        Math.max 0, Math.min 100, @self.personalityReduce 'partyLeavePercent', [@self, @base.partyLeavePercent], @base.partyLeavePercent

      classChangePercent: (potential) ->
        @base.classChangePercent = 100
        Math.max 0, Math.min 100, @self.personalityReduce 'classChangePercent', [@self, potential, @base.classChangePercent], @base.classChangePercent

      alignment: ->
        @base.alignment = 0
        Math.max -10, Math.min 10, @self.personalityReduce 'alignment', [@self, @base.alignment], @base.alignment

      ascendChance: ->
        @base.ascendChance = 100
        Math.max 0, Math.min 100, @self.personalityReduce 'ascendChance', [@self, @base.ascendChance], @base.ascendChance

      descendChance: ->
        @base.descendChance = 100
        Math.max 0, Math.min 100, @self.personalityReduce 'descendChance', [@self, @base.descendChance], @base.descendChance

      teleportChance: ->
        @base.teleportChance = 100
        Math.max 0, Math.min 100, @self.personalityReduce 'teleportChance', [@self, @base.teleportChance], @base.teleportChance

      fallChance: ->
        @base.fallChance = 100
        Math.max 0, Math.min 100, @self.personalityReduce 'fallChance', [@self, @base.fallChance], @base.fallChance

      physicalAttackTargets: (allEnemies, allCombatMembers) ->
        allEnemies = {probability: 100, result: allEnemies} if _.isArray allEnemies
        (@self.probabilityReduce 'physicalAttackTargets', [@self, allEnemies, allCombatMembers], allEnemies).result

      magicalAttackTargets: (allEnemies, allCombatMembers) ->
        allEnemies = {probability: 100, result: allEnemies} if _.isArray allEnemies
        (@self.probabilityReduce 'magicalAttackTargets', [@self, allEnemies, allCombatMembers], allEnemies).result

Character::num2dir = (dir,x,y) ->
  switch dir
    when 1 then return {x: x-1, y: y-1}
    when 2 then return {x: x, y: y-1}
    when 3 then return {x: x+1, y: y-1}
    when 4 then return {x: x-1, y: y}

    when 6 then return {x: x+1, y: y}
    when 7 then return {x: x-1, y: y+1}
    when 8 then return {x: x, y: y+1}
    when 9 then return {x: x+1, y: y+1}

    else return {x: x, y: y}

module.exports = exports = Character
