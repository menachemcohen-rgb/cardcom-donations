trigger ContactNormalizationTrigger on Contact(before insert, before update) {
  ContactNormalization.apply(Trigger.new);
}
