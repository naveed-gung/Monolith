ok and i asked to do the same for the md files !!!!!!!!!!!!!!!!!!!!!!!
what about them
and the main readme file i want professional svg icons next to the titles and the diagrams and svgs in the readme.md ahave broken text layout !!!
nino@nino MINGW64 ~/Documents/Work/Personal/Mobile/Flutter projects/Monolith (main)
$ flutter run -d emulator-5554
Launching lib\main.dart on sdk gphone64 x86 64 in debug mode...

FAILURE: Build failed with an exception.

* What went wrong:
Configuration cache state could not be cached: field `queue` of `java.util.WeakHashMap` bean found in field `values` of `org.jetbrains.kotlin.gradle.utils.StoredPropertyStorage` bean found in field `storage` of `org.gradle.internal.extensibility.DefaultExtraPropertiesExtension` bean found in field `extraProperties` of `com.android.build.gradle.internal.services.ProjectServices` bean found in field `projectServices` of `com.android.build.gradle.internal.services.VariantServicesImpl` bean found in field `variantServices` of `com.android.build.api.variant.impl.BundleConfigImpl` bean found in field `bundleConfig` of `com.android.build.api.variant.impl.ApplicationVariantImpl_Decorated` bean found in field `$it` of `com.flutter.gradle.DependencyVersionChecker$configureMinSdkCheck$1$minSdkCheckTask$1$1` bean found in field `action` of `org.gradle.api.internal.AbstractTask$TaskActionWrapper` bean found in field `actions` of task `:app:DebugMinSdkCheck` of type `org.gradle.api.DefaultTask`: error writing value of type 'java.lang.ref.ReferenceQueue'

> Unable to make field private volatile java.lang.ref.Reference java.lang.ref.ReferenceQueue.head accessible: module java.base does not "opens java.lang.ref" to unnamed module @f48e66d

* Try:

> Run with --stacktrace option to get the stack trace.
> Run with --info or --debug option to get more log output.
> Run with --scan to get full insights.
> Get more help at <https://help.gradle.org>.

BUILD FAILED in 6s
Running Gradle task 'assembleDebug'...                              6.7s
Error: Gradle task assembleDebug failed with exit code 1

nino@nino MINGW64 ~/Documents/Work/Personal/Mobile/Flutter projects/Monolith (main)
$
Show less
