import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rodajusta_core/rodajusta_core.dart';

import '../../servicos/api.dart';
import '../../widgets/comum.dart';

/// Etapa 2 do entregador: documentos, veículo e plano.
class CadastroEntregador extends StatefulWidget {
  const CadastroEntregador({super.key});
  @override
  State<CadastroEntregador> createState() => _CadastroEntregadorState();
}

class _CadastroEntregadorState extends State<CadastroEntregador> {
  final _cpf = TextEditingController();
  final _placa = TextEditingController();
  String _veiculo = 'moto';
  String _plano = 'por_entrega';
  String? _zona;
  String? _cnh;
  String? _selfie;

  Future<String?> _foto(String nome, {bool camera = false}) async {
    final img = await ImagePicker().pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 80,
      preferredCameraDevice: CameraDevice.front,
    );
    if (img == null || !mounted) return null;
    final caminho = 'docs/$uid/$nome.jpg';
    return executar(context, () async {
      await FirebaseStorage.instance.ref(caminho).putData(await img.readAsBytes(), SettableMetadata(contentType: 'image/jpeg'));
      return caminho;
    });
  }

  Future<void> _enviar() async {
    await executar(context, () => chamar('completarCadastroEntregador', {
          'cpf': _cpf.text,
          'veiculo': _veiculo,
          'placa': _placa.text,
          'plano': _plano,
          'cnhPath': _cnh ?? '',
          'selfiePath': _selfie ?? '',
          'zonaId': _zona ?? '',
        }));
  }

  @override
  Widget build(BuildContext context) {
    final precisaCnh = _veiculo != 'bike';
    final pronto = _cpf.text.replaceAll(RegExp(r'\D'), '').length == 11 &&
        _selfie != null &&
        (!precisaCnh || (_cnh != null && _placa.text.trim().length >= 7));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete seu cadastro'),
        actions: [TextButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('Sair'))],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: db.doc('config/parametros').snapshots(),
        builder: (context, snap) {
          final taxa = Map<String, dynamic>.from(snap.data?.data()?['taxa'] as Map? ?? {});
          final porEntrega = (taxa['porEntregaCentavos'] as num? ?? 80).toInt();
          final mensal = (taxa['mensalCentavos'] as num? ?? 8000).toInt();
          final compensa = (mensal / porEntrega).ceil();
          return ListView(padding: const EdgeInsets.all(16), children: [
            TextField(
              controller: _cpf,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'CPF'),
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'moto', label: Text('Moto'), icon: Icon(Icons.two_wheeler)),
                ButtonSegment(value: 'carro', label: Text('Carro'), icon: Icon(Icons.directions_car)),
                ButtonSegment(value: 'bike', label: Text('Bike'), icon: Icon(Icons.pedal_bike)),
              ],
              selected: {_veiculo},
              onSelectionChanged: (s) => setState(() => _veiculo = s.first),
            ),
            if (precisaCnh) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _placa,
                onChanged: (_) => setState(() {}),
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Placa'),
              ),
              _BotaoFoto(
                titulo: 'Foto da CNH',
                feito: _cnh != null,
                aoTocar: () async {
                  final c = await _foto('cnh');
                  if (c != null) setState(() => _cnh = c);
                },
              ),
            ],
            _BotaoFoto(
              titulo: 'Selfie (rosto bem visível)',
              feito: _selfie != null,
              aoTocar: () async {
                final c = await _foto('selfie', camera: true);
                if (c != null) setState(() => _selfie = c);
              },
            ),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: db.collection('zonas').where('ativa', isEqualTo: true).snapshots(),
              builder: (context, z) {
                final zonas = z.data?.docs ?? [];
                if (zonas.isEmpty) return const SizedBox.shrink();
                return DropdownButtonFormField<String>(
                  initialValue: _zona,
                  decoration: const InputDecoration(labelText: 'Onde você trabalha'),
                  items: [for (final d in zonas) DropdownMenuItem(value: d.id, child: Text(d.data()['nome'] as String? ?? d.id))],
                  onChanged: (v) => setState(() => _zona = v),
                );
              },
            ),
            const SizedBox(height: 24),
            Text('Plano com a plataforma', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('O mensal compensa a partir de $compensa entregas no mês. Dá para trocar depois (vale no mês seguinte).'),
            RadioGroup<String>(
              groupValue: _plano,
              onChanged: (v) => setState(() => _plano = v ?? _plano),
              child: Column(children: [
                RadioListTile(value: 'por_entrega', title: Text('Por entrega: ${formatarReais(porEntrega)} cada')),
                RadioListTile(value: 'mensal', title: Text('Mensal: ${formatarReais(mensal)} por mês')),
              ]),
            ),
            const Text('O pagamento à plataforma é feito por fora (Pix) e registrado pelo administrador.'),
          ]);
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(onPressed: pronto ? _enviar : null, child: const Text('Enviar para análise')),
        ),
      ),
    );
  }
}

class _BotaoFoto extends StatelessWidget {
  const _BotaoFoto({required this.titulo, required this.feito, required this.aoTocar});
  final String titulo;
  final bool feito;
  final VoidCallback aoTocar;
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(top: 12),
        child: ListTile(
          leading: Icon(feito ? Icons.check_circle : Icons.photo_camera_outlined, color: feito ? Colors.green : null),
          title: Text(titulo),
          subtitle: Text(feito ? 'Enviada' : 'Toque para enviar'),
          onTap: aoTocar,
        ),
      );
}
