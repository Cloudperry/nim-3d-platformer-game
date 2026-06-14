# Sovelluksen release version suorittaminen ja testien ajaminen (suositus)

1. Lataa pelin pakattu release etsimällä [täältä](https://github.com/Cloudperry/nim-3d-platformer-game/releases) uusimman version.tar.xz tiedosto
2. Pura release komennolla `archive="<release name>.tar.xz" && tar -xJf "$archive" && cd "${archive%.tar.xz}"` tai haluamallasi graafisella työkalulla
3. Pelin voi suorittaa komennolla `./platformer-game` terminaalissa, jonka työkansio on purettu release versio
4. Testit voi suorittaa komennolla `./platformer-game-tests`

# Kääntäminen lähdekoodista

1. Asenna Nim Choosenim -työkalun avulla [näillä ohjeilla](https://nim-lang.org/install_unix.html)
2. Kloonaa repositorio komennolla `git clone -b course-release https://github.com/Cloudperry/nim-3d-platformer-game.git && cd nim-3d-platformer-game`
3. Suorita repositorion kansiossa komento `nimble install` asentaaksesi sovelluksen oman käyttäjän kotikansion alle tai `nimble build -d:release` luodaksesi suoritettavan binäärin repositorioon `bin` kansion alle
4. Pelin voi suorittaa komennolla `./bin/platformer-game` 
5. Testit voi suorittaa komennolla `nimble test` samassa kansiossa