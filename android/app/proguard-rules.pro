# Keep kotlinx serialization generated serializers.
-if @kotlinx.serialization.Serializable class *
-keep,includedescriptorclasses class <1>$$serializer { *; }
-keepclassmembers class **$$serializer { *; }
