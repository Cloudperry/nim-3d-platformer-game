This branch documents the benchmarks done at the end of section 4.3.

Instructions to run the benchmarks:
1. Clone the repository using `git clone -b sphere-tracing-dynamic-scene-perfloss https://github.com/Cloudperry/nim-opengl-csg`
2. Compile the program using instructions in the main branch README.md
3. Run command `gl_zink ./bin/sdf-renderer -s=<slang path> --camLockX=-6.7099457 --camLockY=1.3805737 --camLockZ=5.5620604 --camLockYaw=1.2324038 --camLockPitch=-0.15819687 --lockTime=2.0`. Replace \<slang path\> in the command with the path where you extracted Slang. Keep the renderer running for at least a few seconds to get enough data.
4. Enable the interpreter by running the command `git checkout 40d98064f2e65ffc64f4ee8c8295f6483a109f07` and recompiling the program
5. Run command from step 3 again to get performance data with the interpreter enabled
