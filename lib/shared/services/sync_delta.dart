/// Which entity groups changed during a sync / WS pull.
class SyncDelta {
  final bool medicines;
  final bool sales;
  final bool patients;
  final bool appointments;
  final bool prescriptions;
  final bool templates;
  final bool settings;
  final bool users;
  final bool transfers;

  const SyncDelta({
    this.medicines = false,
    this.sales = false,
    this.patients = false,
    this.appointments = false,
    this.prescriptions = false,
    this.templates = false,
    this.settings = false,
    this.users = false,
    this.transfers = false,
  });

  static const all = SyncDelta(
    medicines: true,
    sales: true,
    patients: true,
    appointments: true,
    prescriptions: true,
    templates: true,
    settings: true,
    users: true,
    transfers: true,
  );

  static const none = SyncDelta();

  bool get isEmpty =>
      !medicines &&
      !sales &&
      !patients &&
      !appointments &&
      !prescriptions &&
      !templates &&
      !settings &&
      !users &&
      !transfers;

  SyncDelta merge(SyncDelta other) => SyncDelta(
        medicines: medicines || other.medicines,
        sales: sales || other.sales,
        patients: patients || other.patients,
        appointments: appointments || other.appointments,
        prescriptions: prescriptions || other.prescriptions,
        templates: templates || other.templates,
        settings: settings || other.settings,
        users: users || other.users,
        transfers: transfers || other.transfers,
      );

  @override
  String toString() =>
      'SyncDelta(med=$medicines sales=$sales patients=$patients appt=$appointments rx=$prescriptions tpl=$templates set=$settings users=$users transfers=$transfers)';
}

