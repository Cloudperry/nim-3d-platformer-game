# 3D platformer

Tämä on mahdollisimman yksinkertainen 3D platformer peli, jossa pelaaja voi juosta, hyppiä ja hypätä seinästä. Tasoissa on mahdollista käyttää pelkästään laatikoita ja niitä ei voi kääntää. Pelaajan liikkuminen on suunnilleen Counter-Strike 1.6 kaltainen, mutta nopeus on nopeampi ja pelaaja voi lisäksi hypätä seinästä.

Pelissä ei ole tällä hetkellä mitään tavoitetta, mutta testitasossa voi taitavilla seinähypyillä päästä katolle. Tämä näytetään testin `walljumpParkourTest1` käyttämässä uusinnassa.

Peli on tehty Nim ohjelmointikielellä ja OpenGL grafiikkakirjastolla.

# Dokumentaatio
- [Käyttöohje ja asennus](dokumentaatio/ohje.md)
- [Vaatimusmäärittely](dokumentaatio/vaatimusmaarittely.md)
- [Arkkitehtuurikuvaus](dokumentaatio/arkkitehtuuri.md)
- [Testausdokumentti](dokumentaatio/testaus.md)
- [Työaikakirjanpito](dokumentaatio/tuntikirjanpito.md)

# Projektin historia

Tein 2025 syksyllä kandityön 3D renderöinnistä säteenseurannan (ray tracing) kaltaisesta renderöintialgoritmista nimeltä sphere tracing. Kandityön ohella koodasin algoritmin repositorioon https://github.com/Cloudperry/nim-opengl-csg. Ennen algoritmin koodausta harjoittelin vähän OpenGL:n käyttöä tekemällä yleisemmin käytetyillä rasterization tekniikoilla yksinkertaisen 3D grafiikkasovelluksen, jossa voi lentää kameralla. Tämä projekti perustuu kandityön koodausprojektiin ja olen merkinnyt tuntikirjanpitoon myös kaiken tähän uuteen projektiin liittyvän työn vuodelta 2025. Suurin osa tästä projektista on kuitenkin tehty vuoden 2026 keväällä ja kesällä.

# Nim

Nim pitäisi olla melko helppoa ymmärtää Pythonia ja staattisesti tyypitettyjä kieliä kuten C++:aa osaavalle. Aikaisemmassa projektissani https://github.com/Cloudperry/the-witness-puzzle-maker on ehkä vielä helpommin ymmärrettävää Nim koodia ja jonkun verran kommentteja Nimin oudommista ominaisuuksista.