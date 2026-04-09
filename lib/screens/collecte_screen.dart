import 'package:flutter/material.dart';

import '../data/sample_chart_data.dart';
import '../models/app_role.dart';
import '../models/user_profile.dart';
import '../services/gestia_data_service.dart';
import '../widgets/charts/tax_breakdown_pie_card.dart';
import '../widgets/payment_form_card.dart';
import '../widgets/responsive_two_cards.dart';

class CollecteScreen extends StatefulWidget {
  const CollecteScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<CollecteScreen> createState() => _CollecteScreenState();
}

class _CollecteScreenState extends State<CollecteScreen> {
  List<TaxSlice> _slices = [];
  bool _loadingPie = true;

  String? get _scope =>
      widget.profile.role.isGlobalSupervisor ? null : widget.profile.communeId;

  Future<void> _loadPie() async {
    setState(() => _loadingPie = true);
    try {
      final tax = await GestiaDataService.taxBreakdownLast30Days(
        communeId: _scope,
      );
      if (!mounted) return;
      setState(() {
        _slices = tax;
        _loadingPie = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingPie = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPie();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Saisie des Recettes',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          ResponsiveTwoCards(
            left: PaymentFormCard(
              profile: widget.profile,
              onSaved: _loadPie,
            ),
            right: Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Utilisateur connecté',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.profile.fullName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      widget.profile.displayLine,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Divider(height: 24),
                    if (_loadingPie)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else
                      TaxBreakdownPieCard(
                        title: 'Recettes (30 j.)',
                        compact: true,
                        slices: _slices,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
