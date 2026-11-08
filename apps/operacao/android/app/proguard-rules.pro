# O plugin de OCR referencia os modelos de chinês, japonês, coreano e
# devanágari; o RodaJusta usa só o alfabeto latino (não incluídos no APK).
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Serviço e receptores da impressora virtual (declarados no manifesto)
-keep class br.com.rodajusta.operacao.** { *; }
