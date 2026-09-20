package io.paratoner.tesseract_ocr;

import io.flutter.embedding.engine.plugins.FlutterPlugin;

/**
 * Registration compatibility for tesseract_ocr's Dart and iOS dependency.
 * Android OCR runs only through FirePin's firepin/identity_ocr channel.
 */
public final class TesseractOcrPlugin implements FlutterPlugin {
    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {
        // GeneratedPluginRegistrant requires this class; no Android channel is registered.
    }

    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {
        // No resources or channel were registered.
    }
}
