class EmpresaConfig {
  final String? logoUrl;
  final String ruc;
  final String razonSocial;
  final String direccion;
  final String telefono;
  final String? ticketHeader;
  final String? ticketFooter;
  final String? pdfTerminos;

  EmpresaConfig({
    this.logoUrl,
    required this.ruc,
    required this.razonSocial,
    required this.direccion,
    required this.telefono,
    this.ticketHeader,
    this.ticketFooter,
    this.pdfTerminos,
  });

  factory EmpresaConfig.fromMap(Map<String, dynamic> map) {
    return EmpresaConfig(
      logoUrl: map['logo_url'],
      ruc: map['ruc'] ?? '',
      razonSocial: map['razon_social'] ?? map['nombre_comercial'] ?? '',
      direccion: map['direccion'] ?? '',
      telefono: map['telefono'] ?? '',
      ticketHeader: map['ticket_header'],
      ticketFooter: map['ticket_footer'],
      pdfTerminos: map['pdf_terminos'] ?? map['terminos_pdf'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'logo_url': logoUrl,
      'ruc': ruc,
      'razon_social': razonSocial,
      'direccion': direccion,
      'telefono': telefono,
      'ticket_header': ticketHeader,
      'ticket_footer': ticketFooter,
      'pdf_terminos': pdfTerminos,
    };
  }

  EmpresaConfig copyWith({
    String? logoUrl,
    String? ruc,
    String? razonSocial,
    String? direccion,
    String? telefono,
    String? ticketHeader,
    String? ticketFooter,
    String? pdfTerminos,
  }) {
    return EmpresaConfig(
      logoUrl: logoUrl ?? this.logoUrl,
      ruc: ruc ?? this.ruc,
      razonSocial: razonSocial ?? this.razonSocial,
      direccion: direccion ?? this.direccion,
      telefono: telefono ?? this.telefono,
      ticketHeader: ticketHeader ?? this.ticketHeader,
      ticketFooter: ticketFooter ?? this.ticketFooter,
      pdfTerminos: pdfTerminos ?? this.pdfTerminos,
    );
  }
}
