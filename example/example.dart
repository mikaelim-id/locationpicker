import 'package:flutter/material.dart';
import 'package:locationpicker/place_picker.dart';

class PickerDemo extends StatefulWidget {
  const PickerDemo({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => PickerDemoState();
}

class PickerDemoState extends State<PickerDemo> {
  LocationResult? _result;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Picker Example')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.place_outlined),
              label: const Text('Pick delivery location'),
              onPressed: showPlacePicker,
            ),
            if (_result != null) ...[
              const SizedBox(height: 24),
              Text(_result!.name ?? '',
                  style: Theme.of(context).textTheme.titleMedium),
              Text(_result!.formattedAddress ?? ''),
            ],
          ],
        ),
      ),
    );
  }

  void showPlacePicker() async {
    final LocationResult? result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PlacePicker('YOUR_API_KEY'),
      ),
    );

    if (result != null) {
      setState(() => _result = result);
    }
  }
}
