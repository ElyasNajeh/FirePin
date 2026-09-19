import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../features/onboarding/onboarding_models.dart';
import '../../theme/app_theme.dart';
import 'motion.dart';

class DigitInput extends StatefulWidget {
  const DigitInput({
    super.key,
    required this.controller,
    required this.label,
    required this.length,
    this.obscure = false,
    this.onComplete,
    this.focusNode,
    this.enabled = true,
  });
  final TextEditingController controller;
  final String label;
  final int length;
  final bool obscure;
  final ValueChanged<String>? onComplete;
  final FocusNode? focusNode;
  final bool enabled;
  @override
  State<DigitInput> createState() => _DigitInputState();
}

class _DigitInputState extends State<DigitInput> {
  late final FocusNode _focus = widget.focusNode ?? FocusNode();
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focus.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.removeListener(_changed);
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final digits = widget.controller.text;
    final pin = widget.length == 4;
    final reduce = AppMotion.reduced(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: pin ? 270 : 342),
        child: SizedBox(
          height: pin ? 66 : 58,
          child: Stack(
            children: [
              // A single real field supplies editing, paste, keyboard, autofill,
              // focus and screen-reader semantics. Cells never compete for focus.
              Positioned.fill(
                child: TextField(
                  key: ValueKey(widget.label),
                  controller: widget.controller,
                  focusNode: _focus,
                  enabled: widget.enabled,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  autofillHints: widget.obscure
                      ? null
                      : const [AutofillHints.oneTimeCode],
                  enableSuggestions: false,
                  autocorrect: false,
                  enableIMEPersonalizedLearning: false,
                  obscureText: widget.obscure,
                  enableInteractiveSelection: !widget.obscure,
                  showCursor: false,
                  style: const TextStyle(color: Colors.transparent),
                  cursorColor: Colors.transparent,
                  decoration: InputDecoration(
                    labelText: widget.label,
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                    labelStyle: const TextStyle(color: Colors.transparent),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  inputFormatters: [
                    TextInputFormatter.withFunction(
                      (oldValue, newValue) => newValue.copyWith(
                        text: normalizeDigits(newValue.text),
                      ),
                    ),
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(widget.length),
                  ],
                  onChanged: (value) {
                    if (value.length == widget.length) {
                      widget.onComplete?.call(value);
                    }
                  },
                  onSubmitted: (value) {
                    if (value.length == widget.length) {
                      widget.onComplete?.call(value);
                    }
                  },
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: Row(
                      spacing: pin ? 14 : 10,
                      // The first cell is rightmost, as in the Arabic Figma frames.
                      children: List.generate(widget.length, (index) {
                        final filled = index < digits.length;
                        final active =
                            widget.enabled &&
                            index ==
                                (digits.length < widget.length
                                    ? digits.length
                                    : widget.length - 1);
                        return Expanded(
                          child: AnimatedContainer(
                            duration: reduce ? Duration.zero : AppMotion.press,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(
                                pin ? 15 : 13,
                              ),
                              border: Border.all(
                                color: active
                                    ? AppColors.primary
                                    : AppColors.outline,
                                width: active ? 2 : 1,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: AnimatedSwitcher(
                              duration: reduce
                                  ? Duration.zero
                                  : AppMotion.press,
                              transitionBuilder: (child, animation) =>
                                  ScaleTransition(
                                    scale: Tween<double>(
                                      begin: 0.85,
                                      end: 1,
                                    ).animate(animation),
                                    child: FadeTransition(
                                      opacity: animation,
                                      child: child,
                                    ),
                                  ),
                              child: Text(
                                filled
                                    ? (widget.obscure ? '●' : digits[index])
                                    : '',
                                key: ValueKey(filled ? digits[index] : ''),
                                style: AppType.text(
                                  widget.obscure ? 18 : 22,
                                  weight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
