import Foundation

/// Polilínea codificada (el formato de Google que usan Valhalla y OSRM).
/// Valhalla usa 6 decimales.
public enum Polilinea {
    public static func decodificar(_ texto: String, precision: Int = 6) -> [PuntoRuta] {
        let factor = pow(10.0, Double(precision))
        let bytes = Array(texto.utf8)
        var indice = 0
        var latitud = 0
        var longitud = 0
        var puntos: [PuntoRuta] = []

        func siguiente() -> Int? {
            var resultado = 0
            var desplazamiento = 0
            while indice < bytes.count {
                let valor = Int(bytes[indice]) - 63
                indice += 1
                resultado |= (valor & 0x1F) << desplazamiento
                desplazamiento += 5
                if valor < 0x20 {
                    return (resultado & 1) != 0 ? ~(resultado >> 1) : (resultado >> 1)
                }
            }
            return nil
        }

        while indice < bytes.count {
            guard let incrementoLatitud = siguiente(), let incrementoLongitud = siguiente() else { break }
            latitud += incrementoLatitud
            longitud += incrementoLongitud
            puntos.append(PuntoRuta(latitud: Double(latitud) / factor, longitud: Double(longitud) / factor))
        }
        return puntos
    }

    public static func codificar(_ puntos: [PuntoRuta], precision: Int = 6) -> String {
        let factor = pow(10.0, Double(precision))
        var bytes: [UInt8] = []
        var latitudAnterior = 0
        var longitudAnterior = 0

        func anadir(_ valor: Int) {
            var resto = valor < 0 ? ~(valor << 1) : (valor << 1)
            while resto >= 0x20 {
                bytes.append(UInt8((0x20 | (resto & 0x1F)) + 63))
                resto >>= 5
            }
            bytes.append(UInt8(resto + 63))
        }

        for punto in puntos {
            let latitud = Int((punto.latitud * factor).rounded())
            let longitud = Int((punto.longitud * factor).rounded())
            anadir(latitud - latitudAnterior)
            anadir(longitud - longitudAnterior)
            latitudAnterior = latitud
            longitudAnterior = longitud
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
