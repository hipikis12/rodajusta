/// Rótulos em português dos status gravados pelo servidor.
const rotulosStatusLote = {
  'buscando': 'Buscando entregador',
  'aceito': 'Entregador a caminho da loja',
  'coletado': 'Saiu para entrega',
  'concluido': 'Concluído',
  'sem_entregador': 'Sem entregador',
  'cancelado': 'Cancelado',
};

const rotulosStatusPedido = {
  'buscando': 'Buscando entregador',
  'aguardando_inclusao': 'Aguardando o entregador aceitar',
  'aceito': 'Aguardando coleta',
  'coletado': 'Em rota',
  'entregue': 'Entregue',
  'nao_entregue': 'Não entregue',
  'sem_entregador': 'Sem entregador',
  'cancelado': 'Cancelado',
};

const rotulosMotivoBloqueio = {
  'cadastro_incompleto': 'Complete seu cadastro para ficar online.',
  'aguardando_aprovacao': 'Seu cadastro está em análise.',
  'bloqueado': 'Sua conta está bloqueada. Fale com o suporte.',
  'fatura_atrasada': 'Sua fatura está atrasada. Pague para voltar a receber entregas.',
  'mock': 'Desative apps de localização falsa para ficar online.',
};

String rotulo(Map<String, String> mapa, String? chave) => mapa[chave] ?? (chave ?? '');
