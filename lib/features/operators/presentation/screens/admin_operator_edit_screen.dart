import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../database/supabase_providers.dart';
import '../../../../database/repositories/supabase_operators_repository.dart';
import '../../../../main.dart';
import '../../../../routing/route_paths.dart';
import '../../../../shared/widgets/snackbar_helper.dart';
import '../../../../shared/widgets/form_container.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../devices/presentation/notifiers/devices_list_notifier.dart';
import '../../../logsheet/presentation/notifiers/plant_logsheet_providers.dart';
import '../notifiers/operator_form_notifier.dart';

class AdminOperatorEditScreen extends ConsumerStatefulWidget {
  const AdminOperatorEditScreen({super.key, required this.operatorId, this.operator});

  final String operatorId;
  final SupabaseOperator? operator;

  @override
  ConsumerState<AdminOperatorEditScreen> createState() => _AdminOperatorEditScreenState();
}

class _AdminOperatorEditScreenState extends ConsumerState<AdminOperatorEditScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _phoneController;
  final Set<String> _selectedDeviceIds = {};
  final Set<String> _selectedDepartmentIds = {};
  bool _initializedDevices = false;

  @override
  void initState() {
    super.initState();
    final op = widget.operator;
    _nameController = TextEditingController(text: op?.fullName ?? '');
    _usernameController = TextEditingController(text: op?.username ?? '');
    _phoneController = TextEditingController(text: '');
    if (op != null && op.allottedDepartmentIds.isNotEmpty) {
      _selectedDepartmentIds.addAll(op.allottedDepartmentIds);
    }
    
    _fetchAssignedDevices();
  }

  Future<void> _fetchAssignedDevices() async {
    final devicesRepo = ref.read(supabaseDevicesRepoProvider);
    final assignments = await devicesRepo.getAssignedToOperator(widget.operatorId);

    // If operator was passed without allotted departments, fetch operator record
    if (widget.operator == null || widget.operator!.allottedDepartmentIds.isEmpty) {
      final op = await ref.read(supabaseOperatorsRepoProvider).findById(widget.operatorId);
      if (op != null && op.allottedDepartmentIds.isNotEmpty) {
        _selectedDepartmentIds.addAll(op.allottedDepartmentIds);
      }
    }

    if (mounted) {
      setState(() {
        _selectedDeviceIds.addAll(assignments.map((e) => e.id));
        _initializedDevices = true;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    final notifier = ref.read(operatorFormNotifierProvider.notifier);
    final allDepts = ref.read(allPlantDepartmentsProvider).value ?? [];
    final selectedNames = allDepts
        .where((d) => _selectedDepartmentIds.contains(d.id))
        .map((d) => d.name)
        .toList();

    await notifier.editOperator(
      operatorId: widget.operatorId,
      fullName: _nameController.text,
      username: _usernameController.text,
      phoneNumber: _phoneController.text,
      assignedDeviceIds: _selectedDeviceIds.toList(),
      allottedDepartmentIds: _selectedDepartmentIds.toList(),
      allottedDepartmentNames: selectedNames,
    );

    if (!mounted) return;
    
    final state = ref.read(operatorFormNotifierProvider);
    if (state.success) {
      SnackbarHelper.showSuccess(context, 'Operator updated successfully');
      // Go back to dashboard to refresh list properly
      context.go(RoutePaths.adminDashboard); 
    } else if (state.error != null) {
      SnackbarHelper.showError(context, state.error!);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.operator == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Operator')),
        body: const Center(child: Text('Operator data missing')),
      );
    }

    final formState = ref.watch(operatorFormNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Operator'),
      ),
      body: FormContainer(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 20),
            
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 20),
            
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _onSubmit(),
            ),
            
            const SizedBox(height: 24),
            Text('Assign Devices', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            
            if (!_initializedDevices)
              const Align(alignment: Alignment.centerLeft, child: CircularProgressIndicator())
            else
              ref.watch(devicesListProvider).when(
                  data: (devices) {
                    final activeDevices = devices.where((d) => d.isActive).toList();
                    if (activeDevices.isEmpty) {
                      return const Text('No active devices available.');
                    }
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: activeDevices.map((device) {
                        final isSelected = _selectedDeviceIds.contains(device.id);
                        return FilterChip(
                          label: Text(device.name),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedDeviceIds.add(device.id);
                              } else {
                                _selectedDeviceIds.remove(device.id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    );
                  },
                  loading: () => const Align(alignment: Alignment.centerLeft, child: CircularProgressIndicator()),
                  error: (err, _) => Text('Error loading devices: $err'),
                ),
            
            const SizedBox(height: 24),

            Text(
              'Allot Plant Divisions / Departments',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Operator will only see logs and equipments for their allotted divisions.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            ref.watch(allPlantDepartmentsProvider).when(
                  data: (departments) {
                    if (departments.isEmpty) {
                      return const Text('No divisions available. Go to Manage Departments to add.');
                    }
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: departments.map((dept) {
                        final isSelected = _selectedDepartmentIds.contains(dept.id);
                        return FilterChip(
                          avatar: isSelected ? null : const Icon(Icons.business_outlined, size: 16),
                          label: Text('${dept.name} (${dept.code})'),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedDepartmentIds.add(dept.id);
                              } else {
                                _selectedDepartmentIds.remove(dept.id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    );
                  },
                  loading: () => const Align(
                    alignment: Alignment.centerLeft,
                    child: CircularProgressIndicator(),
                  ),
                  error: (err, _) => Text(
                    'Error loading divisions: $err',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),

            const SizedBox(height: 40),
            
            AppButton(
              label: 'Save Changes',
              isLoading: formState.isLoading,
              onPressed: _onSubmit,
            ),
          ],
        ),
      ),
      ),
    );
  }
}
