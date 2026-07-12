import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:printing/printing.dart';
import '../../../../shared/models/doctor.dart';
import '../../../../shared/services/printing_service.dart';
import '../../../../theme/app_theme.dart';
import '../../widgets/settings_widgets.dart';

class StoreDetailsSection extends StatelessWidget {
  final TextEditingController storeNameCtrl;
  final TextEditingController addressCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController gstCtrl;
  final TextEditingController clinicNameCtrl;
  final TextEditingController clinicAddressCtrl;
  final TextEditingController clinicPhoneCtrl;
  final TextEditingController clinicRegCtrl;
  final TextEditingController taxCtrl;
  
  final bool isCompositionScheme;
  final int? selectedDefaultDoctorId;
  final List<Doctor> doctors;
  
  final ValueChanged<bool> onCompositionSchemeChanged;
  final ValueChanged<int?> onDefaultDoctorChanged;

  const StoreDetailsSection({
    super.key,
    required this.storeNameCtrl,
    required this.addressCtrl,
    required this.phoneCtrl,
    required this.gstCtrl,
    required this.clinicNameCtrl,
    required this.clinicAddressCtrl,
    required this.clinicPhoneCtrl,
    required this.clinicRegCtrl,
    required this.taxCtrl,
    required this.isCompositionScheme,
    required this.selectedDefaultDoctorId,
    required this.doctors,
    required this.onCompositionSchemeChanged,
    required this.onDefaultDoctorChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'STORE & CLINICAL IDENTITY',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: AppTheme.primaryLight,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Update details printed on receipts, customer invoices, and clinical dispense logs.',
                style: TextStyle(fontSize: 12, color: context.textMutedColor),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final useHorizontal = constraints.maxWidth > 1000;
            
            final storeCard = SettingsSection(
              title: 'Store Information',
              icon: LucideIcons.building,
              children: [
                SettingsField(controller: storeNameCtrl, label: 'Store Name', icon: LucideIcons.building),
                SettingsField(controller: addressCtrl, label: 'Store Address', icon: LucideIcons.mapPin),
                Row(
                  children: [
                    Expanded(child: SettingsField(controller: phoneCtrl, label: 'Store Phone', icon: LucideIcons.phone)),
                    const SizedBox(width: 16),
                    Expanded(child: SettingsField(controller: gstCtrl, label: 'GST Number', icon: LucideIcons.fileText)),
                  ],
                ),
                const SizedBox(height: 16),
                SettingsSwitch(
                  title: 'GST Composition Scheme',
                  subtitle: 'Tax is not collected from customers',
                  value: isCompositionScheme,
                  icon: LucideIcons.percent,
                  onChanged: (val) {
                    onCompositionSchemeChanged(val);
                    if (val) {
                      taxCtrl.text = '0.0';
                    }
                  },
                ),
              ],
            );

            final clinicCard = SettingsSection(
              title: 'Clinic / Doctor Details',
              icon: LucideIcons.stethoscope,
              children: [
                SettingsField(controller: clinicNameCtrl, label: 'Clinic / Doctor Name', icon: LucideIcons.stethoscope),
                SettingsField(controller: clinicAddressCtrl, label: 'Physical Address', icon: LucideIcons.mapPin),
                Row(
                  children: [
                    Expanded(child: SettingsField(controller: clinicPhoneCtrl, label: 'Contact Phone', icon: LucideIcons.phone)),
                    const SizedBox(width: 16),
                    Expanded(child: SettingsField(controller: clinicRegCtrl, label: 'Medical Reg No.', icon: LucideIcons.fileText)),
                  ],
                ),
                const Divider(height: 24),
                SettingsDropdown<int?>(
                  title: 'Default Prescribing Doctor',
                  value: doctors.any((d) => d.id == selectedDefaultDoctorId) ? selectedDefaultDoctorId : null,
                  icon: LucideIcons.userCheck,
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('None (Manual Entry)'),
                    ),
                    ...doctors.map((d) => DropdownMenuItem<int?>(
                          value: d.id,
                          child: Text(d.name),
                        )),
                  ],
                  onChanged: onDefaultDoctorChanged,
                ),
              ],
            );

            if (useHorizontal) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: storeCard),
                  const SizedBox(width: 24),
                  Expanded(child: clinicCard),
                ],
              );
            } else {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  storeCard,
                  clinicCard,
                ],
              );
            }
          },
        ),
      ],
    );
  }
}

class PrintingSection extends StatelessWidget {
  final TextEditingController footerCtrl;
  final TextEditingController currencyCtrl;
  final TextEditingController taxCtrl;
  final String paperSize;
  final String selectedPrinter;
  final bool autoPrint;
  final bool showBatchExpiryRetail;
  final bool showBatchExpiryClinical;
  final bool showOpdIdInPrint;
  final List<Printer> printers;
  final bool isCompositionScheme;
  
  final ValueChanged<String> onPaperSizeChanged;
  final ValueChanged<String> onPrinterChanged;
  final ValueChanged<bool> onAutoPrintChanged;
  final ValueChanged<bool> onShowBatchExpiryRetailChanged;
  final ValueChanged<bool> onShowBatchExpiryClinicalChanged;
  final ValueChanged<bool> onShowOpdIdInPrintChanged;

  const PrintingSection({
    super.key,
    required this.footerCtrl,
    required this.currencyCtrl,
    required this.taxCtrl,
    required this.paperSize,
    required this.selectedPrinter,
    required this.autoPrint,
    required this.showBatchExpiryRetail,
    required this.showBatchExpiryClinical,
    required this.showOpdIdInPrint,
    required this.printers,
    required this.isCompositionScheme,
    required this.onPaperSizeChanged,
    required this.onPrinterChanged,
    required this.onAutoPrintChanged,
    required this.onShowBatchExpiryRetailChanged,
    required this.onShowBatchExpiryClinicalChanged,
    required this.onShowOpdIdInPrintChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'INVOICE & PRINT HARDWARE CONFIG',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: AppTheme.accent,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Adjust default billing rates, receipt layout details, active thermal/document printers, and hardware actions.',
                style: TextStyle(fontSize: 12, color: context.textMutedColor),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final useHorizontal = constraints.maxWidth > 1000;
            
            final styleCard = SettingsSection(
              title: 'Invoice Styling',
              icon: LucideIcons.receipt,
              children: [
                SettingsField(controller: footerCtrl, label: 'Receipt Footer Message', icon: LucideIcons.messageSquare),
                Row(
                  children: [
                    Expanded(child: SettingsField(controller: currencyCtrl, label: 'Currency Symbol', icon: LucideIcons.banknote)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: SettingsField(
                        controller: taxCtrl, 
                        label: isCompositionScheme ? 'Tax Rate (%) (Locked)' : 'Tax Rate (%)', 
                        icon: LucideIcons.percent, 
                        keyboardType: TextInputType.number,
                        enabled: !isCompositionScheme,
                      ),
                    ),
                  ],
                ),
              ],
            );

            final hardwareCard = SettingsSection(
              title: 'Printer Hardware',
              icon: LucideIcons.printer,
              children: [
                SettingsDropdown<String>(
                  title: 'Paper Type',
                  value: paperSize,
                  icon: LucideIcons.fileText,
                  items: const [
                    DropdownMenuItem(value: 'A6', child: Text('A6 (Standard)')),
                    DropdownMenuItem(value: 'Letter', child: Text('Letter')),
                    DropdownMenuItem(value: 'A4', child: Text('A4')),
                    DropdownMenuItem(value: 'Roll80', child: Text('Thermal Roll (80mm)')),
                  ],
                  onChanged: (val) {
                    if (val != null) onPaperSizeChanged(val);
                  },
                ),
                const Divider(),
                SettingsDropdown<String>(
                  title: 'Active Printer',
                  value: printers.any((p) => p.name == selectedPrinter) ? selectedPrinter : '',
                  icon: LucideIcons.printer,
                  items: [
                    const DropdownMenuItem(value: '', child: Text('No Printer Selected')),
                    ...printers.map((p) => DropdownMenuItem(value: p.name, child: Text(p.name))),
                  ],
                  onChanged: (val) {
                    if (val != null) onPrinterChanged(val);
                  },
                ),
                const Divider(),
                SettingsSwitch(
                  title: 'Direct Mode',
                  subtitle: 'Skip print preview and print immediately on checkout',
                  value: autoPrint,
                  icon: LucideIcons.zap,
                  onChanged: onAutoPrintChanged,
                ),
                const Divider(),
                SettingsSwitch(
                  title: 'Show Batch & Expiry (Retail)',
                  subtitle: 'Show Batch number and Expiry date on retail receipts',
                  value: showBatchExpiryRetail,
                  icon: LucideIcons.calendar,
                  onChanged: onShowBatchExpiryRetailChanged,
                ),
                const Divider(),
                SettingsSwitch(
                  title: 'Show Batch & Expiry (Dispense)',
                  subtitle: 'Show Batch number and Expiry date on clinical dispense slips',
                  value: showBatchExpiryClinical,
                  icon: LucideIcons.calendar,
                  onChanged: onShowBatchExpiryClinicalChanged,
                ),
                const Divider(),
                SettingsSwitch(
                  title: 'Show OPD Transaction ID',
                  subtitle: 'Show OPD ID on final dispense receipts',
                  value: showOpdIdInPrint,
                  icon: LucideIcons.receipt,
                  onChanged: onShowOpdIdInPrintChanged,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => PrintingService.instance.testPrint(context),
                    icon: const Icon(LucideIcons.type, size: 16),
                    label: const Text('Send Diagnostic Print'),
                  ),
                ),
              ],
            );

            if (useHorizontal) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: styleCard),
                  const SizedBox(width: 24),
                  Expanded(child: hardwareCard),
                ],
              );
            } else {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  styleCard,
                  hardwareCard,
                ],
              );
            }
          },
        ),
      ],
    );
  }
}
