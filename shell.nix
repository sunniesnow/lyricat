{ pkgs ? import <nixpkgs> {} }: with pkgs; mkShell {
	packages = [
		opencc
		ruby_4_0
	];
	shellHook = ''
		export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${lib.makeLibraryPath [
			opencc
		]}
	'';
}
