import 'package:flutter/material.dart';

class CustomSearchBar extends StatelessWidget {
  const CustomSearchBar({
    super.key,
    required this.onChanged,
    this.controller,
    this.hint = 'Search products',
  });
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final String hint;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: onChanged,
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      prefixIcon: const Icon(Icons.search),
      hintText: hint,
      suffixIcon: controller?.text.isNotEmpty == true
          ? IconButton(
              onPressed: () {
                controller!.clear();
                onChanged('');
              },
              icon: const Icon(Icons.close),
            )
          : null,
    ),
  );
}
