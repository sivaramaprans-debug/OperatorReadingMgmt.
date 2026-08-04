import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/snackbar_helper.dart';
import '../../../../shared/widgets/form_container.dart';
import '../../../devices/presentation/notifiers/devices_list_notifier.dart';
import '../notifiers/operator_form_notifier.dart';

class AdminOperatorCreateScreen extends ConsumerStatefulWidget {
  const AdminOperatorCreateScreen({super.key});

  @override
  ConsumerState<AdminOperatorCreateScreen> createState() => _AdminOperatorCreateScreenState();
}

class _AdminOperatorCreateScreenState extends ConsumerState<AdminOperatorCreateScreen> {
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _obscurePassword = true;
  final Set<String> _selectedDeviceIds = {};

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    final notifier = ref.read(operatorFormNotifierProvider.notifier);
    await notifier.createOperator(
      fullName: _nameController.text,
      username: _usernameController.text,
      password: _passwordController.text,
      phoneNumber: _phoneController.text,
      assignedDeviceIds: _selectedDeviceIds.toList(),
    );

    if (!mounted) return;
    
    final state = ref.read(operatorFormNotifierProvider);
    if (state.success) {
      SnackbarHelper.showSuccess(context, 'Operator created successfully');
      context.pop();
    } else if (state.error != null) {
      SnackbarHelper.showError(context, state.error!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(operatorFormNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Operator'),
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
                hintText: 'e.g. John Doe',
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
                hintText: 'min 4 chars, letters/numbers',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 20),
            
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                hintText: 'e.g. +1234567890',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 20),
            
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: 'Password',
                hintText: 'Min 8 chars, 1 letter, 1 number',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _onSubmit(),
            ),
            const SizedBox(height: 24),
            
            Text(
              'Assign Devices',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
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
                  loading: () => const Align(
                    alignment: Alignment.centerLeft,
                    child: CircularProgressIndicator(),
                  ),
                  error: (err, _) => Text(
                    'Error loading devices: $err',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
                
            const SizedBox(height: 40),
            
            AppButton(
              label: 'Create Operator',
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
