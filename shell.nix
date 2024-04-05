{ pkgs ? import <nixpkgs> {} }: with pkgs; mkShell {
	packages = [
		opencc
	];
	shellHook = ''
		export LD_LIBRARY_PATH=${lib.makeLibraryPath [
			opencc
		]}
	'';
}
