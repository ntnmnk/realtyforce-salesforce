public with sharing class ABCErrors {
  public static AuraHandledException toAuraException(Exception ex) {
    String message = toUserMessage(ex);
    AuraHandledException handledException = new AuraHandledException(message);
    handledException.setMessage(message);
    return handledException;
  }
  public static String toUserMessage(Exception ex) {
    if (ex instanceof ABCException)
      return ex.getMessage();
    if (ex instanceof DmlException) {
      DmlException dmlException = (DmlException) ex;
      if (dmlException.getNumDml() > 0) {
        String errorCode = dmlException.getDmlStatusCode(0);
        if (errorCode == 'FIELD_CUSTOM_VALIDATION_EXCEPTION')
          return dmlException.getDmlMessage(0);
        if (errorCode == 'UNABLE_TO_LOCK_ROW')
          return 'Records are being updated by another user. Please retry.';
        if (
          errorCode == 'INSUFFICIENT_ACCESS_OR_READONLY' ||
          errorCode == 'INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY'
        )
          return 'You do not have permission to update the selected records.';
      }
    }
    System.debug(
      LoggingLevel.ERROR,
      ex.getTypeName() +
        ': ' +
        ex.getMessage() +
        '\n' +
        ex.getStackTraceString()
    );
    return 'Unable to complete the request. Refresh and try again, or contact your administrator.';
  }
}
