#!/usr/bin/env python

from pathlib import Path
import os
import stat
import subprocess
import sys

def is_user_exec(filepath: str) -> bool:
  st = os.stat(filepath)
  return bool(st.st_mode & stat.S_IXUSR)

def exec_cmd(args: [str]) -> str:
  process = subprocess.Popen(args, stdout=subprocess.PIPE,  stderr=subprocess.STDOUT)
  (out, err) = process.communicate()
  retcode = process.wait()
  if retcode != 0:
    print('Warning: Process {0} exited with return code {1}'.format(args, retcode))
  return str(out)

def does_binary_refer_loader(filepath: str) -> bool:
  out = exec_cmd(['ldd', filepath])
  return "/ld-" in out

def patch_loader(filepath: str, patchelf: str, new_loader:str):
  new_loader_dir = str(Path(filepath).parent)
  exec_cmd([patchelf, '--set-interpreter', new_loader, '--set-rpath', new_loader_dir, filepath])

def patch_binaries_in_folder(directory : str, patchelf: str, new_loader: str):
  paths = Path(directory).glob('**/*')
  for path in paths:
      path_str: str = os.path.realpath(path)
      # Check for exec bit
      if path.is_file() and is_user_exec(path_str) and does_binary_refer_loader(path_str):
          print("Patching " + path_str)
          patch_loader(path_str, patchelf, new_loader)

# patch_binaries_in_folder("<Code>/LIM_RLBox/build/obj-ff-dbg/dist/bin",
#   "<Code>/LIM_RLBox/build/patchelf-0.10/src/patchelf",
#   "<Code>/LIM_RLBox/build/glibc/glibc-2.30_install/lib/ld-2.30.so")

def main(argv: [str]):
  if len(argv) != 3:
    sys.exit("Usage patch_binaries.py folder_with_binaries_to_patch patchelf_path new_loader_path")
  patch_binaries_in_folder(argv[0], argv[1], argv[2])

if __name__ == "__main__":
   main(sys.argv[1:])