cmake_minimum_required( VERSION 3.4.1 )

add_library( llama SHARED IMPORTED GLOBAL )
set_target_properties( llama PROPERTIES IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/src/main/jniLibs/${ANDROID_ABI}/libllama.so )

add_library( llava SHARED IMPORTED GLOBAL )
set_target_properties( llava PROPERTIES IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/src/main/jniLibs/${ANDROID_ABI}/libllava.so )