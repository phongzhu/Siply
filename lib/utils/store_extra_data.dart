import '../models/voucher.dart';
import '../models/announcement.dart';

class StoreExtraData {
  static Map<String, List<Voucher>> vouchers = {
    's1': [
      Voucher(
        title: '15% OFF on all drinks',
        description: 'Get 15% off your total bill for a limited time!',
        code: 'COCO15',
      ),
      Voucher(
        title: 'Buy 1 Get 1',
        description: 'Buy any large drink and get a medium drink free.',
        code: 'BOGOCOCO',
      ),
    ],
  };

  static Map<String, List<Announcement>> announcements = {
    's1': [
      Announcement(
        title: 'New Branch Opening!',
        body: 'We are now open at SM Baliuag. Visit us for exclusive promos!',
      ),
      Announcement(
        title: 'Holiday Hours',
        body: 'We are open from 10am to 8pm during the holidays.',
      ),
    ],
  };

  static List<Voucher> getVouchersForStore(String storeId) {
    return vouchers[storeId] ?? [];
  }

  static List<Announcement> getAnnouncementsForStore(String storeId) {
    return announcements[storeId] ?? [];
  }
}
