This branch documents the benchmarks done related to the Fig. 4.3. 

Instructions to run the benchmarks:
1. Clone the repository using `git clone -b sphere-tracing-inconsistent-perf https://github.com/Cloudperry/nim-opengl-csg`
2. Compile the program using instructions in the main branch README.md
3. Run commands `./bin/sdf-renderer -s=<slang path> --camLockX=-0.17560759 --camLockY=0.71293163 --camLockZ=-3.4554825 --camLockYaw=-3.1361449 --camLockPitch=-0.11596 --lockTime=3.0` and `./bin/sdf-renderer -s=<slang path> --camLockX=-8.664624 --camLockY=2.7919462 --camLockZ=8.594413 --camLockYaw=0.80879027 --camLockPitch=-0.57017946 --lockTime=3.0` to render the scene from both perspectives shown in Fig. 4.3. Replace \<slang path\> in the commands with the path where you extracted Slang. Keep the renderer running for at least a few seconds to get enough data.
4. Disable the step count limit by running the command `git checkout d9aff3bf4c13cac45e2116f2511926fc34a8c59f` and recompiling the program
5. Run commands from step 3 again to get performance data with the step count limit disabled
