/**
 * Central business constants for ABC Real Estate.
 */
public with sharing class ABCConstants {
  public static final String STATUS_OPEN = 'Open';
  public static final String STATUS_WORKING = 'Working';
  public static final String STATUS_CLOSED_PENDING = 'Closed Pending Approval';
  public static final String STATUS_CLOSED_APPROVED = 'Closed Approved';

  public static final Integer MAX_WORKING_PER_AGENT = 5;
  public static final Integer PAGE_SIZE = 5;

  // Agency commission rate: 3%.
  public static final Decimal AGENCY_COMMISSION_RATE = 0.03;
}
