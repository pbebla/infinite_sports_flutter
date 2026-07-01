import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:infinite_sports_flutter/misc/web_view_stack.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Renders an ordered [RegQuestion] list with flutter_form_builder fields.
/// Required questions gate submission (validation on press); the answers map
/// passed to [onSubmit] has input hygiene applied (see [cleanAnswers]:
/// capitalized/trimmed names, digits-only phone, MM/DD/YYYY dates).
class DynamicRegistrationForm extends StatefulWidget {
  final List<RegQuestion> questions;
  final Map<String, dynamic> initialValues;
  final String submitLabel;
  final Future<void> Function(Map<String, dynamic> answers) onSubmit;

  const DynamicRegistrationForm({
    super.key,
    required this.questions,
    required this.initialValues,
    required this.submitLabel,
    required this.onSubmit,
  });

  @override
  State<DynamicRegistrationForm> createState() =>
      _DynamicRegistrationFormState();
}

class _DynamicRegistrationFormState extends State<DynamicRegistrationForm> {
  final GlobalKey<FormBuilderState> _formKey = GlobalKey<FormBuilderState>();
  bool _submitting = false;

  InputDecoration _decoration(RegQuestion q) => InputDecoration(
        border: const OutlineInputBorder(),
        labelText: q.label,
        hintText:
            (q.type == 'linkAcknowledge' || q.hint.isEmpty) ? null : q.hint,
      );

  Widget _buildField(RegQuestion q) {
    switch (q.type) {
      case 'shortText':
        return FormBuilderTextField(
          name: q.key,
          initialValue: widget.initialValues[q.key]?.toString(),
          textCapitalization: TextCapitalization.words,
          decoration: _decoration(q),
          validator: q.isRequired ? FormBuilderValidators.required() : null,
        );
      case 'paragraph':
        return FormBuilderTextField(
          name: q.key,
          initialValue: widget.initialValues[q.key]?.toString(),
          maxLines: 5,
          keyboardType: TextInputType.multiline,
          decoration: _decoration(q),
          validator: q.isRequired ? FormBuilderValidators.required() : null,
        );
      case 'number':
        return FormBuilderTextField(
          name: q.key,
          initialValue: widget.initialValues[q.key]?.toString(),
          keyboardType: TextInputType.number,
          decoration: _decoration(q),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return q.isRequired ? 'This field is required' : null;
            }
            return num.tryParse(value.trim()) == null ? 'Enter a number' : null;
          },
        );
      case 'phone':
        final initialPhone =
            formatPhone(widget.initialValues[q.key]?.toString() ?? '');
        return FormBuilderTextField(
          name: q.key,
          initialValue: initialPhone,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            MaskTextInputFormatter(
              mask: '(###) ###-####',
              filter: {'#': RegExp(r'[0-9]')},
              initialText: initialPhone,
            ),
          ],
          decoration: _decoration(q),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return q.isRequired ? 'This field is required' : null;
            }
            return normalizePhone(value).length == 10
                ? null
                : 'Enter a 10-digit phone number';
          },
        );
      case 'email':
        return FormBuilderTextField(
          name: q.key,
          initialValue: widget.initialValues[q.key]?.toString(),
          keyboardType: TextInputType.emailAddress,
          decoration: _decoration(q),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return q.isRequired ? 'This field is required' : null;
            }
            return FormBuilderValidators.email()(value);
          },
        );
      case 'date':
        return FormBuilderDateTimePicker(
          name: q.key,
          inputType: InputType.date,
          decoration: _decoration(q),
          validator: q.isRequired ? FormBuilderValidators.required() : null,
        );
      case 'dropdown':
        final initial = widget.initialValues[q.key];
        return FormBuilderDropdown<String>(
          name: q.key,
          initialValue:
              (initial is String && q.options.contains(initial)) ? initial : null,
          decoration: _decoration(q),
          items: q.options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          validator: q.isRequired ? FormBuilderValidators.required() : null,
        );
      case 'singleChoice':
        final initial = widget.initialValues[q.key];
        return FormBuilderRadioGroup<String>(
          name: q.key,
          initialValue:
              (initial is String && q.options.contains(initial)) ? initial : null,
          decoration: _decoration(q),
          orientation: OptionsOrientation.vertical,
          options: q.options
              .map((o) => FormBuilderFieldOption(value: o, child: Text(o)))
              .toList(),
          validator: q.isRequired ? FormBuilderValidators.required() : null,
        );
      case 'multiChoice':
        final initial = widget.initialValues[q.key];
        return FormBuilderCheckboxGroup<String>(
          name: q.key,
          initialValue: initial is List
              ? initial
                  .map((o) => o.toString())
                  .where(q.options.contains)
                  .toList()
              : null,
          decoration: _decoration(q),
          orientation: OptionsOrientation.vertical,
          options: q.options
              .map((o) => FormBuilderFieldOption(value: o, child: Text(o)))
              .toList(),
          validator: q.isRequired ? FormBuilderValidators.required() : null,
        );
      case 'yesNo':
        return FormBuilderRadioGroup<String>(
          name: q.key,
          decoration: _decoration(q),
          orientation: OptionsOrientation.horizontal,
          options: const [
            FormBuilderFieldOption(value: 'Yes', child: Text('Yes')),
            FormBuilderFieldOption(value: 'No', child: Text('No')),
          ],
          validator: q.isRequired ? FormBuilderValidators.required() : null,
        );
      case 'linkAcknowledge':
        return _LinkAcknowledgeField(question: q);
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _submit() async {
    final state = _formKey.currentState;
    if (state == null || !state.saveAndValidate()) return;
    final answers =
        cleanAnswers(widget.questions, Map<String, dynamic>.from(state.value));
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(answers);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormBuilder(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(15),
        children: [
          for (final q in widget.questions)
            Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: _buildField(q),
            ),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(widget.submitLabel,
                      style: const TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Waiver/rules acknowledgement: a tile that must be tapped — opening its URL
/// (stored in the question's hint) in an in-app web view — before its checkbox
/// reads true. Required questions block submission until read. With an empty
/// URL, tapping simply marks it read.
class _LinkAcknowledgeField extends StatelessWidget {
  final RegQuestion question;
  const _LinkAcknowledgeField({required this.question});

  @override
  Widget build(BuildContext context) {
    return FormBuilderField<bool>(
      name: question.key,
      initialValue: false,
      validator: (value) => (question.isRequired && value != true)
          ? 'Please open and read this first'
          : null,
      builder: (field) {
        final read = field.value == true;
        return Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          child: ListTile(
            title: Text(question.label,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: field.errorText != null
                ? Text(field.errorText!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))
                : Text(read ? 'Read — thank you!' : 'Tap to open and read'),
            trailing: Checkbox(value: read, onChanged: null),
            onTap: () async {
              final url = question.hint.trim();
              if (url.isNotEmpty) {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (context) {
                  final controller = WebViewController()
                    ..loadRequest(Uri.parse(url));
                  return Scaffold(
                    appBar: AppBar(
                      centerTitle: true,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      title: Text(question.label),
                    ),
                    body: WebViewStack(controller: controller),
                  );
                }));
              }
              field.didChange(true);
            },
          ),
        );
      },
    );
  }
}
