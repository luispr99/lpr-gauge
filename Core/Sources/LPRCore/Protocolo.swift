// Constantes del protocolo BLE móvil → cuadro. La fuente de verdad es
// docs/PROTOCOLO.md (borrador v0.5): si cambia el documento, cambia esto.

public enum Protocolo {
    /// Versión del formato de los mensajes (sección 3).
    public static let version: UInt8 = 1

    /// Servicio y características (sección 2). Comparten la base
    /// f464xxxx-813a-45b8-8ca8-f5f9e18c21d1.
    public enum UUIDs {
        public static let servicio   = "f4640001-813a-45b8-8ca8-f5f9e18c21d1"
        public static let deviceInfo = "f4640002-813a-45b8-8ca8-f5f9e18c21d1"
        public static let nav        = "f4640003-813a-45b8-8ca8-f5f9e18c21d1"
        public static let gps        = "f4640004-813a-45b8-8ca8-f5f9e18c21d1"
        public static let status     = "f4640005-813a-45b8-8ca8-f5f9e18c21d1"
        public static let navText    = "f4640006-813a-45b8-8ca8-f5f9e18c21d1"
        public static let movil      = "f4640008-813a-45b8-8ca8-f5f9e18c21d1"
        public static let trazo      = "f4640009-813a-45b8-8ca8-f5f9e18c21d1"
    }

    /// Sin recibir datos durante este tiempo, el cuadro muestra el aviso (sección 10).
    public static let caducidadSegundos = 5

    /// La app reenvía el estado al menos con este periodo, aunque no cambie (sección 10).
    public static let mantenimientoSegundos = 2
}
