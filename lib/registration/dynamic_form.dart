import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
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
      case 'height':
        return _HeightField(
          question: q,
          initialValue: widget.initialValues[q.key]?.toString(),
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

/// Height question: a feet + inches pair composed into a single "F'I" answer
/// string (e.g. "6'1"), wrapped in a [FormBuilderField] so required-gating and
/// saveAndValidate participate like every other field. Prefills by splitting
/// an existing "F'I"-style value back into the two boxes.
class _HeightField extends StatefulWidget {
  final RegQuestion question;
  final String? initialValue;
  const _HeightField({required this.question, this.initialValue});

  @override
  State<_HeightField> createState() => _HeightFieldState();
}

class _HeightFieldState extends State<_HeightField> {
  late final TextEditingController _feet;
  late final TextEditingController _inches;

  @override
  void initState() {
    super.initState();
    final parts = (widget.initialValue ?? '').split("'");
    _feet = TextEditingController(text: parts.isNotEmpty ? parts[0] : '');
    _inches = TextEditingController(text: parts.length > 1 ? parts[1] : '');
  }

  @override
  void dispose() {
    _feet.dispose();
    _inches.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    return FormBuilderField<String>(
      name: q.key,
      initialValue: widget.initialValue,
      validator: (value) => (q.isRequired &&
              (value == null || value.trim().isEmpty || value.trim() == "'"))
          ? 'This field is required'
          : null,
      builder: (field) {
        void update() {
          final feet = _feet.text.trim();
          final inches = _inches.text.trim();
          field.didChange((feet.isEmpty && inches.isEmpty)
              ? null
              : "$feet'$inches");
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(q.label,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: Theme.of(context).hintColor)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _feet,
                    keyboardType: TextInputType.number,
                    maxLength: 1,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Feet',
                      counterText: '',
                    ),
                    onChanged: (_) => update(),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: TextField(
                    controller: _inches,
                    keyboardType: TextInputType.number,
                    maxLength: 2,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Inches',
                      counterText: '',
                    ),
                    onChanged: (_) => update(),
                  ),
                ),
              ],
            ),
            if (field.errorText != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(field.errorText!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        );
      },
    );
  }
}

/// Waiver/rules acknowledgement: a tile that must be tapped — opening its URL
/// in an in-app web view — before its checkbox reads true. Required questions
/// block submission until read.
///
/// URL resolution (lazy, on first tap): the question's hint if non-empty;
/// otherwise the legacy RTDB document for well-known keys ('rules' ->
/// Sign Ups/Rules, 'waiver' -> Sign Ups/Waiver) via [getSignUpRules] /
/// [getSignUpWaiver]. Only when no URL resolves anywhere does the tile fall
/// back to marking itself read on tap (with a "(no document attached)" note).
///
/// The checkbox becomes checked only after the web view screen has been
/// opened and returned from — matching the old sign-up form's behavior.
class _LinkAcknowledgeField extends StatefulWidget {
  final RegQuestion question;
  const _LinkAcknowledgeField({required this.question});

  @override
  State<_LinkAcknowledgeField> createState() => _LinkAcknowledgeFieldState();
}

class _LinkAcknowledgeFieldState extends State<_LinkAcknowledgeField> {
  bool _resolving = false;
  String? _resolvedUrl; // '' once resolution finds nothing anywhere

  Future<String> _resolveUrl() async {
    final hintUrl = widget.question.hint.trim();
    if (hintUrl.isNotEmpty) return hintUrl;
    try {
      switch (widget.question.key) {
        case 'rules':
          return (await getSignUpRules()).trim();
        case 'waiver':
          return (await getSignUpWaiver()).trim();
        default:
          return '';
      }
    } catch (e) {
      // Defensive: getSignUpRules/getSignUpWaiver call
      // FirebaseDatabase.instance before their own try/catch, so a
      // not-yet-initialized Firebase app (or any other lookup failure)
      // would otherwise crash the tile instead of degrading to "no
      // document attached".
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.question;
    return FormBuilderField<bool>(
      name: question.key,
      initialValue: false,
      validator: (value) => (question.isRequired && value != true)
          ? 'Please open and read this first'
          : null,
      builder: (field) {
        final read = field.value == true;
        String subtitle;
        if (field.errorText != null) {
          subtitle = field.errorText!;
        } else if (read) {
          subtitle = 'Read — thank you!';
        } else if (_resolving) {
          subtitle = 'Loading…';
        } else if (_resolvedUrl == '') {
          subtitle = 'Tap to mark as read (no document attached)';
        } else {
          subtitle = 'Tap to open and read';
        }
        return Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          child: ListTile(
            title: Text(question.label,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(subtitle,
                style: field.errorText != null
                    ? TextStyle(color: Theme.of(context).colorScheme.error)
                    : null),
            trailing: _resolving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Checkbox(value: read, onChanged: null),
            onTap: _resolving
                ? null
                : () async {
                    var url = _resolvedUrl;
                    if (url == null) {
                      setState(() => _resolving = true);
                      url = await _resolveUrl();
                      if (!mounted) return;
                      setState(() {
                        _resolvedUrl = url;
                        _resolving = false;
                      });
                    }
                    if (url.isNotEmpty) {
                      if (!context.mounted) return;
                      await Navigator.push(context,
                          MaterialPageRoute(builder: (context) {
                        final controller = WebViewController()
                          ..loadRequest(Uri.parse(url!));
                        return Scaffold(
                          appBar: AppBar(
                            centerTitle: true,
                            backgroundColor:
                                Theme.of(context).colorScheme.primary,
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
