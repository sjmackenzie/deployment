{ stdenv, erlang, rebar }:

{ name, version
, buildInputs ? [], erlangDeps ? []
, postPatch ? ""
, ... }@attrs:

with stdenv.lib;

stdenv.mkDerivation ({
  name = "${name}-${version}";

  buildInputs = buildInputs ++ [ erlang rebar ];

  postPatch = ''
    rm -f rebar
    if [ -e "src/${name}.app.src" ]; then
      sed -i -e 's/{ *vsn *,[^}]*}/{vsn, "${version}"}/' "src/${name}.app.src"
    fi
    ${postPatch}
  '';

  configurePhase = let
    getDeps = drv: [drv] ++ (map getDeps drv.erlangDeps);
    recursiveDeps = uniqList {
      inputList = flatten (map getDeps erlangDeps);
    };
  in ''
    runHook preConfigure
    ${concatMapStrings (dep: ''
      header "linking erlang dependency ${dep}"
      ensureDir deps
      ln -s "${dep}" "deps/${dep.packageName}"
      stopNest
    '') recursiveDeps}
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    rebar compile
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    for reldir in src ebin priv include; do
      [ -e "$reldir" ] || continue
      ensureDir "$out"
      cp -rt "$out" "$reldir"
      success=1
    done
    runHook postInstall
  '';

  passthru = {
    packageName = name;
    inherit erlangDeps;
  };
} // removeAttrs attrs [ "name" "postPatch" "buildInputs" ])
