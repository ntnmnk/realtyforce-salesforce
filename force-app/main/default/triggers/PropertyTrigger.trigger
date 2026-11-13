trigger PropertyTrigger on Property__c (
    before insert, before update,
    after insert, after update,
    after delete, after undelete
) {
    if (Trigger.isBefore) {
        PropertyTriggerHandler.beforeSave(
            Trigger.new,
            Trigger.isUpdate
                ? Trigger.oldMap
                : new Map<Id, Property__c>()
        );
    }

    if (Trigger.isAfter) {
        PropertyTriggerHandler.afterChange(
            Trigger.isDelete ? Trigger.old : Trigger.new,
            Trigger.isUpdate
                ? Trigger.oldMap
                : new Map<Id, Property__c>()
        );
    }
}