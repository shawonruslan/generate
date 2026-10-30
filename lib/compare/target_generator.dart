import '../browser/image_prompt_service.dart';

/// Smart generation (fast path, v1.13): ONE text_to_image request.
/// No reference upload, no image_to_image, no measuring, no regenerate,
/// no Gemini at generation time. Everything smart happens when the
/// prompt is written (element plan in one Gemini call + locally read
/// colours); here the prompt only gets the exact look of the source
/// picture when the similarity target keeps it.
String smartPrompt(String prompt, ImagePromptItem? ref) {
  final p = prompt.trim();
  if (ref == null) return p;
  final target = ref.target;
  if (target < 40) return p; // creative targets: own colours
  final extra = <String>[];
  if (ref.palette.isNotEmpty) {
    extra.add('colour palette ${ref.palette.take(5).join(', ')}');
  }
  if (target >= 55 && ref.tone.isNotEmpty) extra.add('exposure: ${ref.tone}');
  if (extra.isEmpty) return p;
  final sep = p.endsWith('.') ? ' ' : '. ';
  return '$p${sep}Exact look: ${extra.join('; ')}.';
}
