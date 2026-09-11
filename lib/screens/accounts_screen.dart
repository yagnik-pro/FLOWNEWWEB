import 'package:flutter/material.dart';

import '../main.dart';
import '../theme.dart';
import '../models/account.dart';
import '../widgets/brand.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});
  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  final _selected = <String>{};
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _name = TextEditingController();
  bool _obscure = true;
  bool _adding = false;
  String? _formError;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    setState(() { _formError = null; _adding = true; });
    final err = await store.addAccount(_email.text, _pass.text, name: _name.text);
    if (!mounted) return;
    setState(() {
      _adding = false;
      _formError = err;
      if (err == null) { _email.clear(); _pass.clear(); _name.clear(); }
    });
    if (err == null && mounted) {
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account added'), margin: EdgeInsets.all(14)),
      );
    }
  }

  Future<void> _rename(Account a) async {
    final ctl = TextEditingController(text: a.name);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Store name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctl,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'e.g. Sparrow Prime'),
            ),
            const SizedBox(height: 10),
            const Text(
              'Leave it empty to let OTP Flow read the name from your Meesho panel again.',
              style: TextStyle(fontSize: 12, color: AppColors.ink2),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.blue),
            onPressed: () => Navigator.pop(context, ctl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null) await store.renameAccount(a, name);
  }

  Future<void> _confirmDelete(Account a) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Remove account?'),
        content: Text('${a.name} (${a.email}) and its saved OTPs will be deleted from this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes == true) {
      _selected.remove(a.id);
      await store.removeAccount(a);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final accounts = store.accounts;
        final allSelected = accounts.isNotEmpty && _selected.length == accounts.length;

        return Column(
          children: [
            FlowHeader(
              title: 'Accounts',
              subtitle: '${accounts.length} seller account(s) · unlimited',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                children: [
                  if (accounts.isNotEmpty) ...[
                    FlowCard(
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: allSelected,
                                  activeColor: AppColors.blue,
                                  onChanged: (v) => setState(() {
                                    _selected.clear();
                                    if (v == true) _selected.addAll(accounts.map((a) => a.id));
                                  }),
                                ),
                                const Expanded(child: Text('Select all', style: TextStyle(fontWeight: FontWeight.w700))),
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.blue,
                                    padding: const EdgeInsets.symmetric(horizontal: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                                  ),
                                  onPressed: (_selected.isEmpty || store.busy)
                                      ? null
                                      : () => store.reloginAll(accounts.where((a) => _selected.contains(a.id)).toList()),
                                  icon: const Icon(Icons.login_rounded, size: 17),
                                  label: Text(_selected.isEmpty ? 'Relogin' : 'Relogin (${_selected.length})',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ),
                          ),
                          ...accounts.map((a) => _accountTile(a)),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        side: const BorderSide(color: AppColors.skyLine, width: 1.4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                        foregroundColor: AppColors.blueDeep,
                      ),
                      onPressed: store.busy ? null : () => store.refreshAll(),
                      icon: const Icon(Icons.sync_rounded, size: 19),
                      label: Text(store.busy ? (store.busyLabel ?? 'Working…') : 'Refresh all OTPs',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 22),
                  ],
                  const Text('Add seller account', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text('Credentials stay on this phone only.',
                      style: TextStyle(color: AppColors.ink2, fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 12),
                  FlowCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Meesho supplier email',
                            prefixIcon: Icon(Icons.mail_outline_rounded, size: 20),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _pass,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                            suffixIcon: IconButton(
                              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _name,
                          decoration: const InputDecoration(
                            labelText: 'Store name (optional)',
                            hintText: 'Auto-detected from Meesho',
                            prefixIcon: Icon(Icons.storefront_outlined, size: 20),
                          ),
                        ),
                        if (_formError != null) ...[
                          const SizedBox(height: 10),
                          Row(children: [
                            const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.danger),
                            const SizedBox(width: 6),
                            Expanded(child: Text(_formError!, style: const TextStyle(color: AppColors.danger, fontSize: 12.7, fontWeight: FontWeight.w600))),
                          ]),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: AppColors.otpGradient,
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: [BoxShadow(color: AppColors.blue.withOpacity(.32), blurRadius: 14, offset: const Offset(0, 5))],
                            ),
                            child: TextButton(
                              onPressed: _adding ? null : _add,
                              style: TextButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                                foregroundColor: Colors.white,
                              ),
                              child: _adding
                                  ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                      SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.3, color: Colors.white)),
                                      SizedBox(width: 10),
                                      Text('Logging in…', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                                    ])
                                  : const Text('Login', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _accountTile(Account a) {
    final sel = _selected.contains(a.id);
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.skyLine, width: 1))),
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        children: [
          Checkbox(
            value: sel,
            activeColor: AppColors.blue,
            onChanged: (v) => setState(() => v == true ? _selected.add(a.id) : _selected.remove(a.id)),
          ),
          Expanded(
            child: InkWell(
              onTap: () => _rename(a),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(a.name,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 5),
                        const Icon(Icons.edit_outlined, size: 14, color: AppColors.ink2),
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(a.email,
                        style: const TextStyle(fontSize: 11.8, color: AppColors.ink2, fontWeight: FontWeight.w600),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (a.lastError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(a.lastError!,
                            style: const TextStyle(fontSize: 11.3, color: AppColors.danger, fontWeight: FontWeight.w600),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                ),
              ),
            ),
          ),
          _statusPill(a),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: store.busy ? null : () => store.reloginAll([a]),
            icon: a.status == AccStatus.working
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.blue))
                : const Icon(Icons.refresh_rounded, size: 20, color: AppColors.blueDeep),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _confirmDelete(a),
            icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.danger),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(Account a) {
    switch (a.status) {
      case AccStatus.working:
        return const StatusPill('Working', bg: AppColors.sky, fg: AppColors.blueDeep);
      case AccStatus.needsLogin:
        return const StatusPill('Login', bg: Color(0xFFFFF3D6), fg: AppColors.warn);
      case AccStatus.error:
        return const StatusPill('Error', bg: Color(0xFFFDECEA), fg: AppColors.danger);
      default:
        return const StatusPill('Active', bg: AppColors.mintSoft, fg: Color(0xFF1E7A4A));
    }
  }
}
