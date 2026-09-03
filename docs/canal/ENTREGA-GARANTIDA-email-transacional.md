<!--
  ===================================================================
  NOTA DE ARQUIVAMENTO — 03/09/2026, ao entrar no repositório
  ===================================================================

  Repasse técnico de outro desenvolvedor, extraído do código em produção do
  **Enquadria**. Os nomes de arquivo e de tabela são os daquele repositório.

  ELE NÃO É DECISÃO DE PRODUTO DO SESSÕES, E NÃO SE APLICA COMO ESTÁ.

  A arquitetura é boa e a tese é a parte que se leva inteira: *o provedor
  responde `success` quando a mensagem entra na fila dele, não quando o destino
  recebe*. O que não se leva é o esquema — `emails_saida` seria uma segunda
  fonte de verdade sobre "a mensagem saiu?", e este produto já tem essa fonte
  em `public.mensagens`, com `chave_idem`, ciclo de vida e camada manual.

  O que se aproveita, o que se adapta e o que fica bloqueado está em
  `docs/canal/README.md`. A build que aplica isto é a **B55**.
  ===================================================================
-->

# Entrega garantida: confirmação em vez de aceite

**Arquitetura de e-mail transacional — repasse técnico**

Servidor próprio **Postal** na frente, **Brevo** como queda, e um mecanismo que
descobre sozinho quando o Postal parou de entregar — porque a API dele responde
`success` nos dois casos.

Documento extraído do código em produção do Enquadria. Os nomes de arquivo e de
tabela são os daquele repositório; o que importa é a arquitetura, não a
nomenclatura.

---

## A tese

> O Postal responde `"status": "success"` quando a mensagem entra **na fila
> dele** — não quando o destino recebe.

Essa distinção é a razão de tudo o que vem abaixo existir.

A queda para um segundo provedor cobre o servidor **recusar**. Ela não cobre o
caso que de fato aconteceu: o provedor da VPS bloqueou a porta 25 por volume.
Nesse cenário a API responde `success`, o app registra sucesso, e a mensagem
apodrece na fila. O documento não chega e ninguém fica sabendo.

Falha silenciosa em e-mail transacional é a pior classe de defeito que existe
num produto assim: não quebra nada, não aparece em log de erro, e o prejuízo é
um documento jurídico que o cliente jurou ter recebido.

---

## 1. As quatro peças

Nenhuma funciona sozinha. Implementar três das quatro é **pior** do que não
implementar nenhuma — a peça que falta vira conclusão errada nas outras três.

| Peça | Onde roda | O que faz |
|---|---|---|
| **Registro** | no envio | Toda mensagem que sai vira linha em `emails_saida`, com chave idempotente. Sem registro não há como saber o que não chegou. |
| **Confirmação** | webhook | O provedor avisa a entrega e a linha vira `entregue`. O que ficar `aceito` além da janela é considerado perdido. |
| **Reenvio** | cron, 15 min | Perdido pelo caminho próprio sai de novo pelo provedor de queda — **e só o perdido**. Bounce não se reenvia. |
| **Disjuntor** | cron + envio | Se a taxa de perda passa do limite, o caminho de **todos** vira o provedor de queda até haver prova de que o próprio voltou. |

O motivo de existir o disjuntor: sem ele, cada mensagem é descoberta perdida uma
a uma, com 20 minutos de atraso cada. Com ele, a segunda leva de mensagens já
sai pelo caminho bom.

---

## 2. A máquina de estados

Cinco estados e nada além disso. Todo o resto do sistema é a decisão de qual
transição tomar e quando.

```
                          webhook: delivered
              ┌────────────────────────────────────►  entregue
              │
              │           webhook: bounce / spam
   aceito ────┼────────────────────────────────────►  falhou
              │                                        (não se reenvia)
              │
              │           20 min sem notícia          tentativas < 2
              └────────────────────────────────────►  perdido ─────────► reenviado
   o provedor aceitou;                                    │
   ainda sem confirmação                                  │  tentativas >= 2
                                                          └─────────────► desistir
                                                                          (fica visível
                                                                           na tela, sem
                                                                           novo envio)
```

| Estado | Significado |
|---|---|
| `aceito` | O provedor aceitou; ainda não há confirmação de entrega. |
| `entregue` | O provedor confirmou a entrega — fim de linha feliz. |
| `falhou` | O destino recusou (caixa inexistente, bloqueio). **Não se reenvia.** |
| `perdido` | Aceito e sem notícia além da janela: candidato a reenvio. |
| `reenviado` | Saiu por outro caminho; a linha nova é que vale. |

`aceito` é o único estado que a varredura vigia — e **só no caminho próprio**.
Mensagem do provedor de queda resolve síncrono e nunca entra na fila de
vigilância.

---

## 3. O cliente do Postal

Duas coisas que a documentação não deixa óbvias, e as duas custam caro.

### 3.1 O HTTP 200 não decide nada

O Postal responde **200 mesmo em erro**. O resultado real está no campo `status`
do JSON. Quem confia no código HTTP acha que enviou e não enviou.

```ts
// lib/mailer/postal.ts — POST {POSTAL_URL}/api/v1/send/message

const resp = await fetch(`${url}/api/v1/send/message`, {
  method: "POST",
  headers: {
    "X-Server-API-Key": key,      // não é Authorization
    "Content-Type": "application/json",
    Accept: "application/json",
  },
  body: JSON.stringify(corpo),
  signal: controller.signal,       // AbortController, 15s
  cache: "no-store",
});

const bruto = await resp.text();

let json: PostalResposta;
try {
  json = JSON.parse(bruto) as PostalResposta;
} catch {
  return { ok: false, erro: `resposta não-JSON (HTTP ${resp.status}): ${bruto.slice(0, 200)}` };
}

// O status HTTP não decide nada aqui — o campo `status` decide.
if (json.status !== "success") {
  return {
    ok: false,
    codigo: json.data?.code ?? json.status ?? "desconhecido",
    erro: json.data?.message ?? JSON.stringify(json).slice(0, 300),
  };
}

return { ok: true, messageId: json.data?.message_id ?? "", detalhes: json.data?.messages };
```

### 3.2 Cabeçalhos e corpo

- Autenticação em `X-Server-API-Key`, **não** em `Authorization`.
- `AbortController` com timeout de **15 s**. Sem ele, um Postal travado segura a
  rota do app até o limite da plataforma.
- Mensagem só-HTML pontua pior em filtro de spam: se vier `html_body` sem
  `plain_body`, **derive o texto puro** antes de mandar.
- `Auto-Submitted: auto-generated` em todo transacional — reduz resposta
  automática de férias virando ruído e ajuda na classificação.
- Sanitize o nome do destinatário: `replace(/["<>\r\n]/g, "")`. Nome com quebra
  de linha é injeção de cabeçalho.

### 3.3 Formato da mensagem

```ts
type PostalMensagem = {
  to: string[];                    // "Nome <email@dominio>" ou só o e-mail
  from?: string;
  sender?: string;
  subject: string;
  plain_body?: string;
  html_body?: string;
  cc?: string[];
  bcc?: string[];
  reply_to?: string;
  tag?: string;                    // rótulo: separa o que é o quê no painel
  headers?: Record<string, string>;
  attachments?: { name: string; content_type: string; data: string /* base64 */ }[];
};
```

---

## 4. A porta única

Um só arquivo manda e-mail. As dezesseis rotas do app chamam `enviarEmail` e não
sabem por onde a mensagem saiu.

```ts
// lib/email.ts — a assinatura que o resto do app enxerga

enviarEmail({
  para: string,
  nome?: string,
  assunto: string,
  html: string,
  tag?: string,                     // rótulo do provedor
  responderPara?: { email: string; nome?: string },
  referencia?: string | null,       // id do documento — é o que dá idempotência
}): Promise<{
  enviado: boolean,
  caminho: "postal" | "brevo" | "nenhum",
  desviado?: boolean,               // true quando o disjuntor desviou antes de tentar
  motivo?: string,
}>
```

> **A regra que atravessa o arquivo inteiro**
>
> **O registro nunca impede o envio.** Banco fora, migration não rodada, chave de
> serviço ausente — a mensagem sai do mesmo jeito e a auditoria se perde.
> Auditoria que derruba o que audita é pior que auditoria nenhuma.

### 4.1 Como o caminho é escolhido

Duas coisas precisam ser verdadeiras: **configuração** (as variáveis existem?) e
**observação** (ele está entregando?). O disjuntor é a segunda.

```ts
// lib/entrega-garantida.ts — função pura, sem banco e sem rede

export function caminhoDeSaida(
  postalDisponivel: boolean,
  brevoDisponivel: boolean,
  d: Disjuntor
): Caminho {
  if (postalDisponivel && d.estado === "fechado") return "postal";
  if (brevoDisponivel) return "brevo";
  /* sem queda configurada, o Postal aberto ainda é melhor que não mandar:
     mensagem na fila de um servidor com problema tem alguma chance;
     mensagem não enviada tem zero. */
  if (postalDisponivel) return "postal";
  return "nenhum";
}
```

O fluxo do envio, então, é:

1. Calcula a chave idempotente.
2. Lê o disjuntor e decide o caminho.
3. Se o caminho é o de queda, manda por lá e registra — **sem nem tentar o
   Postal**. Já se sabe que ele não está entregando, e cada tentativa vira mais
   uma mensagem represada para a varredura descobrir 20 minutos depois.
4. Se é o caminho normal e o Postal **aceita**: registra como `aceito` (não como
   entregue) e guarda o envelope para eventual reenvio.
5. Se o Postal **recusa** de forma síncrona: cai para a queda na hora e registra
   o motivo da recusa junto.

### 4.2 A idempotência

Reenvio automático sem chave é como um cliente recebe seis vezes o mesmo
documento — e desconfia dos seis.

```ts
export function chaveSaida(tag: string, para: string, referencia?: string | null): string {
  const ref = (referencia ?? "").trim() || "sem-ref";
  return `${tag}:${para.trim().toLowerCase()}:${ref}`;
}
```

A referência é o id do documento quando existe. É o que distingue *"o segundo
laudo desta empresa"* de *"o mesmo laudo de novo"*.

O índice único é sobre **`(chave, caminho)`** e não sobre a chave sozinha: o
reenvio cria linha nova com a mesma chave e caminho diferente, e é isso que
permite auditar *"saiu duas vezes, por caminhos diferentes, porque a primeira não
confirmou"*.

---

## 5. O webhook

Uma porta só para os dois provedores. A tradução mora **fora da rota, sem
banco**, porque é a parte que erra: nome de campo, formato de data, nome do
evento.

Dois endpoints significariam duas normalizações que divergem — e a divergência
apareceria como *"a campanha X não tem abertura nenhuma"*, que se parece com
campanha ruim.

### 5.1 A tabela de tradução

| Evento interno | Postal manda | Brevo manda |
|---|---|---|
| `entregue` | `messagesent` | `delivered` |
| `aberto` | `messageloaded` | `opened`, `unique_opened` |
| `clique` | `messagelinkclicked` | `click` |
| `bounce` | `messagebounced`, `messagedeliveryfailed` | `hard_bounce`, `soft_bounce` |
| `recusado` | — | `blocked`, `invalid_email` |
| `spam` | — | `spam` |

Normalize o nome antes de casar: `cru.toLowerCase().replace(/[^a-z_]/g, "")`.

### 5.2 Três detalhes de formato que já custaram caro

1. **O Postal embrulha o evento em `payload`**; a Brevo manda plano.
   ```ts
   const p = (bruto.payload && typeof bruto.payload === "object")
     ? (bruto.payload as Record<string, unknown>)
     : bruto;
   ```

2. **O Postal manda epoch em segundos.** Tratar como milissegundos joga tudo para
   1970 — e o painel mostra "nenhum evento nos últimos 30 dias", que é
   indistinguível de "a campanha não teve abertura".
   ```ts
   const ms = v < 1e12 ? v * 1000 : v;
   ```

3. **O Postal casa por `message.token`; a Brevo não devolve id que dê para
   casar.** Sem id, confirme pelo **destinatário mais recente ainda em aberto** —
   e só esse: casar por e-mail sem limite marcaria como entregue uma mensagem
   antiga que nunca chegou.

### 5.3 Responda 200 para o evento que você ignora

Evento que não interessa (envio agendado, tipo desconhecido) **não é erro do
provedor** — e provedor que recebe 4xx **desativa o webhook** depois de N falhas.
Perder o canal inteiro por causa de um tipo de evento que você ignora seria uma
falha silenciosa e definitiva.

Vale o mesmo para 5xx: se a gravação falhar, registre no log e devolva 200.

Duplicata do mesmo webhook é **esperada** (retry do provedor) e não é falha:
índice único em `(mensagem_id, evento, ocorreu_em)` e trate `duplicate key` como
sucesso.

### 5.4 O segredo

Vai na query da URL cadastrada no provedor:

```
https://seu-app/api/email/evento?s=SEGREDO
```

Sem a variável no ambiente a rota devolve **503 e não grava** — não é uma rota
que aceita qualquer POST enquanto ninguém configurou nada. Dado de engajamento é
dado de cliente, e escrever no banco a partir de POST anônimo é como uma base de
métricas vira lixo (ou pior, vetor).

Gere com `openssl rand -hex 24`.

### 5.5 O que o webhook faz, em ordem

```
1. confere o segredo                      -> 503 sem variável, 401 se não bater
2. aceita evento único OU lote            -> Array.isArray(corpo) ? corpo : [corpo]
3. normaliza cada item                    -> descarta os que devolvem null
4. se nada sobrou                         -> 200 { ok: true, ignorados: N }
5. CONFIRMA A ENTREGA (o que fecha o ciclo):
     entregue                -> status "entregue"
     bounce | spam | recusado-> status "falhou"
     casa por mensagem_id; se não casar, casa por e-mail
     falha aqui NÃO derruba o webhook (try/catch, log)
6. grava os eventos de engajamento        -> duplicate key = 200
```

---

## 6. A trava contra a conclusão falsa

**A parte mais importante deste documento, e a que quase passou batida na
implementação original.**

Toda a garantia depende de o webhook confirmar entrega. Se ele não estiver ligado
— segredo ausente, URL não cadastrada no painel do provedor, endpoint mudado —,
**nenhuma confirmação chega**. E aí a leitura do sistema fica assim, toda ela
plausível e toda ela errada:

1. nenhuma mensagem confirma → todas viram "perdidas" aos 20 minutos;
2. a varredura reenvia a base inteira pelo provedor de queda, a cada 15 minutos;
3. a taxa de perda dá 100% → o disjuntor abre e desliga o envio próprio.

> **O remédio matando o paciente**
>
> Um webhook desconfigurado derrubaria o servidor que está funcionando
> perfeitamente, duplicaria todo e-mail enviado e queimaria a cota do segundo
> provedor — **sem uma linha de erro em lugar nenhum**.

A trava é simples e não tem exceção: **sem nenhuma confirmação registrada, não se
conclui perda de ninguém.** Ausência total de sinal é falta de instrumento, não
evidência de falha.

```ts
export interface Instrumento {
  temConfirmacoes: boolean;   // houve ao menos uma confirmação na janela?
  totalObservado: number;     // quantas saíram — distingue "silêncio" de "vazio"
}

export function instrumentoConfiavel(i: Instrumento): boolean {
  /* base vazia é um caso legítimo e diferente: não há o que concluir,
     e também não há o que reenviar. Confiável por vacuidade. */
  if (i.totalObservado === 0) return true;
  return i.temConfirmacoes;
}
```

A trava impede o sistema de fazer besteira. Ela **não devolve a proteção**:
enquanto o webhook estiver mudo, mensagem pode se perder sem ninguém saber —
exatamente como antes de tudo isto existir. Por isso o estado cego precisa
*doer*: ele vira alerta vermelho na tela de operação, não uma linha no JSON de
retorno do cron.

### 6.1 O quarto silêncio: o cron parar

Se o cron morrer, nada muda em lugar nenhum — não há erro, não há estado novo, a
ausência é o próprio sintoma. Só a **data da última varredura** denuncia.

Grave essa data a cada execução, inclusive (e principalmente) quando a varredura
se declarar cega, e alerte quando passar de três ciclos — **45 minutos** para um
cron de 15.

---

## 7. Os números, e por que cada um

Todos ajustáveis. Nenhum arbitrário.

| Constante | Valor | Por quê |
|---|---:|---|
| `JANELA_CONFIRMACAO_MIN` | 20 min | Curto demais gera reenvio de mensagem que só estava na fila — o cliente recebe duas. Longo demais é o mesmo que não ter proteção. Entrega normal acontece em segundos; greylisting do destino raramente passa de 15. |
| `TENTATIVAS_MAX` | 2 | Reenviar em laço transforma um problema de entrega num problema de reputação. |
| `AMOSTRA_MINIMA` | 5 | Três mensagens não fazem uma taxa. Abaixo disso o disjuntor não se mexe. |
| `LIMITE_PERDA` | 0,4 (40%) | Perda acima disso na janela recente abre o disjuntor. |
| `HORAS_ATE_SONDAR` | 6 h | Depois disso vale arriscar uma mensagem pelo caminho suspeito. Sem tráfego por ele, nunca haverá amostra provando que voltou. |
| `DIAS_ATE_APAGAR_CORPO` | 7 dias | Teto de retenção do HTML mesmo sem confirmação — senão um webhook quebrado viraria arquivo permanente de dados de terceiros. |
| `MINUTOS_ATE_SUSPEITAR_DO_CRON` | 45 min | Três ciclos sem notícia de um cron de 15 minutos. |
| Intervalo do cron | 15 min | Menor que a janela de confirmação, para que nada fique perdido esperando a próxima passada. |

### 7.1 O disjuntor só fecha por evidência, nunca por tempo

```ts
export function avaliarDisjuntor(atual: Disjuntor, a: Amostra, agoraISO: string): Disjuntor {
  if (a.total < AMOSTRA_MINIMA) return atual;

  const taxa = a.perdidas / a.total;

  if (atual.estado === "fechado" && taxa >= LIMITE_PERDA) {
    return {
      estado: "aberto",
      motivo: `${a.perdidas} de ${a.total} mensagens não confirmaram entrega (${Math.round(taxa * 100)}%)`,
      desde: agoraISO,
    };
  }

  /* fecha só com prova do contrário: nenhuma perda na amostra recente */
  if (atual.estado === "aberto" && a.perdidas === 0) {
    return {
      estado: "fechado",
      motivo: `${a.total} mensagens seguidas confirmaram entrega`,
      desde: agoraISO,
    };
  }

  return atual;
}
```

Disjuntor que fecha sozinho no relógio volta a mandar tudo por um caminho
quebrado e refaz o estrago em silêncio. O que a passagem do tempo autoriza é
**sondar**, que é outra coisa:

```ts
export function deveSondar(d: Disjuntor, agora: Date, horas = HORAS_ATE_SONDAR): boolean {
  if (d.estado !== "aberto" || !d.desde) return false;
  return (agora.getTime() - new Date(d.desde).getTime()) / 3_600_000 >= horas;
}
```

A sonda é o único jeito honesto de fechar o disjuntor: sem tráfego pelo caminho
suspeito, nunca haverá amostra para provar que ele voltou.

---

## 8. O corpo guardado, e a regra da LGPD

Para reenviar **o documento** — e não um aviso dizendo que existe um documento —
é preciso guardar o HTML. Isso é dado de cliente parado no banco, então tem
regra:

1. **Guarde só o que pode precisar de reenvio**: o caminho próprio. Mensagem do
   provedor de queda resolve síncrono e nunca entra na fila de vigilância.
   ```ts
   export function deveGuardarCorpo(caminho: Caminho): boolean {
     return caminho === "postal";
   }
   ```
2. **Guarde o envelope inteiro** — HTML, nome do destinatário e reply-to — para
   que o reenvio seja idêntico, não parecido.
3. **Apague na confirmação.** O corpo existe exatamente enquanto pode ser útil;
   confirmada a entrega, a linha continua (auditoria) e o conteúdo some.
4. **Apague por idade de qualquer jeito**, mesmo sem confirmação. Ponha a faxina
   como **função no banco**, não só como código de aplicação: retenção que
   depende do cron rodar é retenção que some quando o cron falha.
5. **Registre quando e por quê** o corpo foi descartado. Sem isso, "corpo nulo"
   fica ambíguo entre "nunca guardei", "já entreguei" e "expirou".

---

## 9. O esquema

### 9.1 `emails_saida` — o registro de toda mensagem que sai

```sql
create table if not exists public.emails_saida (
  id            uuid primary key default gen_random_uuid(),
  chave         text not null,        -- tag:destinatário:referência
  para          text not null,
  tag           text not null default 'app',
  assunto       text,
  caminho       text not null,        -- postal | brevo
  mensagem_id   text,                 -- id do provedor: o webhook casa por ele
  status        text not null default 'aceito',
  tentativas    int  not null default 0,
  erro          text,
  referencia    text,                 -- id do documento, quando houver
  tenant_id     uuid,
  criado_em     timestamptz not null default now(),
  confirmado_em timestamptz,
  reenviado_em  timestamptz,

  -- só no caminho próprio; apagados na confirmação ou em 7 dias
  corpo_html           text,
  nome_destinatario    text,
  responder_para       text,
  responder_nome       text,
  corpo_apagado_em     timestamptz,
  corpo_apagado_motivo text
);

-- única POR TENTATIVA: o reenvio cria linha nova, mesma chave, outro caminho
create unique index if not exists emails_saida_chave_caminho_idx
  on public.emails_saida (chave, caminho);

-- o índice que a varredura usa a cada 15 minutos
create index if not exists emails_saida_pendentes_idx
  on public.emails_saida (status, caminho, criado_em)
  where status = 'aceito';

create index if not exists emails_saida_mensagem_idx on public.emails_saida (mensagem_id);
create index if not exists emails_saida_data_idx     on public.emails_saida (criado_em desc);

-- a faxina: só as linhas que ainda têm corpo interessam
create index if not exists emails_saida_corpo_idx
  on public.emails_saida (criado_em) where corpo_html is not null;
```

### 9.2 `email_disjuntor` — uma linha, e o motivo por escrito

```sql
create table if not exists public.email_disjuntor (
  id            smallint primary key default 1,
  estado        text not null default 'fechado',   -- fechado | aberto
  motivo        text,
  desde         timestamptz,
  atualizado_em timestamptz not null default now(),
  constraint email_disjuntor_linha_unica  check (id = 1),
  constraint email_disjuntor_estado_valido check (estado in ('fechado', 'aberto'))
);

insert into public.email_disjuntor (id, estado) values (1, 'fechado')
  on conflict (id) do nothing;
```

O `motivo` é obrigatório na prática: quem abrir esta tabela daqui a três meses
precisa saber por que o desvio aconteceu. E `desde` é o que autoriza a sonda.

### 9.3 A faxina como função do banco

```sql
create or replace function public.limpar_corpos_expirados(p_dias int default 7)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_n int;
begin
  update public.emails_saida
     set corpo_html = null,
         corpo_apagado_em = now(),
         corpo_apagado_motivo = 'expirou (' || p_dias || ' dias)'
   where corpo_html is not null
     and criado_em < now() - make_interval(days => p_dias);
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- Função SECURITY DEFINER em `public` vira rota HTTP no PostgREST.
-- Esta é destrutiva (p_dias => 0 apaga tudo). Tranque:
revoke execute on function public.limpar_corpos_expirados(integer)
  from public, anon, authenticated;
grant  execute on function public.limpar_corpos_expirados(integer) to service_role;
```

> **`from public` e não só `from anon, authenticated`.** O ACL padrão traz
> `=X/postgres`, que é o grant para PUBLIC — e `anon` é membro de PUBLIC.
> Revogar só dos papéis nomeados deixa a porta exatamente como estava.

### 9.4 `email_eventos` — abertura, clique e falha

```sql
create table if not exists public.email_eventos (
  id          uuid primary key default gen_random_uuid(),
  envio_id    uuid references public.plataforma_envios(id) on delete set null,
  tenant_id   uuid,
  para        text not null,
  regra       text,          -- a campanha, copiada do envio: agrupa sem join
  evento      text not null, -- entregue | aberto | clique | bounce | spam | recusado
  url         text,          -- para clique: o destino
  provedor    text,
  mensagem_id text,
  ocorreu_em  timestamptz not null default now(),
  criado_em   timestamptz not null default now()
);

-- abertura repetida é informação; DUPLICATA do mesmo webhook não é
create unique index if not exists email_eventos_unico
  on public.email_eventos (coalesce(mensagem_id, ''), evento, ocorreu_em);

create index if not exists email_eventos_regra on public.email_eventos (regra, evento, ocorreu_em desc);
create index if not exists email_eventos_para  on public.email_eventos (para, ocorreu_em desc);
```

Guarde a **URL do clique**: é o que separa "clicou no CTA" de "clicou no
descadastro", que é a diferença entre campanha boa e campanha ruim.

---

## 10. Variáveis de ambiente

Cada ausência tem um comportamento **declarado**. Nenhuma derruba o produto.

| Variável | Sem ela |
|---|---|
| `POSTAL_URL` | o envio cai para o provedor de queda; o log diz por onde saiu |
| `POSTAL_API_KEY` | idem |
| `POSTAL_FROM` | usa o remetente padrão embutido no código |
| `BREVO_API_KEY` | não há queda: o Postal aberto ainda é tentado |
| `BREVO_REMETENTE_EMAIL` · `BREVO_REMETENTE_NOME` | usa o padrão embutido |
| `EMAIL_WEBHOOK_SEGREDO` | **a rota do webhook devolve 503 e não grava** — de propósito |
| `CRON_SECRET` | a varredura recusa toda chamada (401) |
| `MAILER_TEST_SECRET` | a rota de teste devolve 401 e não manda nada |
| `SUPABASE_SERVICE_ROLE_KEY` | o webhook devolve 503; o registro de saída se perde **mas o e-mail sai** |

```bash
# ── servidor de e-mail próprio (Postal) ──────────────────────────────
POSTAL_URL=https://postal.seu-dominio.com.br
POSTAL_API_KEY=
POSTAL_FROM=Produto <nao-responda@seu-dominio.com.br>

# ── queda ────────────────────────────────────────────────────────────
BREVO_API_KEY=
BREVO_REMETENTE_EMAIL=no-reply@seu-dominio.com.br
BREVO_REMETENTE_NOME=Produto

# ── webhook de entrega, abertura e clique ────────────────────────────
# vai na QUERY da URL cadastrada no provedor:
#   https://app.seu-dominio.com.br/api/email/evento?s=SEU_SEGREDO
# gere com: openssl rand -hex 24
EMAIL_WEBHOOK_SEGREDO=

# ── a varredura ──────────────────────────────────────────────────────
CRON_SECRET=

# ── rota de teste; SEM ELA devolve 401 e não manda nada ──────────────
MAILER_TEST_SECRET=
```

> **Rota de teste de e-mail aberta é máquina de spam de graça.**
> `/api/dev/testar-email` exige segredo em header (`x-mailer-secret`) ou query.
> Sem a variável definida ela recusa todo mundo — o padrão é fechado, não aberto.

---

## 11. Ordem de implantação

**Nesta ordem.** Ligar o cron antes do webhook produz exatamente o cenário da
seção 6.

1. **DNS do domínio de envio**: SPF, DKIM e DMARC apontando para o servidor
   próprio, e PTR reverso do IP. O painel do Postal confere os três.
2. **Suba as tabelas** e insira a linha 1 do disjuntor com estado `fechado`.
3. **Cadastre o webhook no provedor**, com o segredo na query. No Postal:
   *Webhooks → adicionar*, marcando `MessageSent`, `MessageDeliveryFailed`,
   `MessageBounced`, `MessageLoaded` e `MessageLinkClicked`.
4. **Confirme que a confirmação chega**: mande um e-mail de teste e verifique que
   a linha em `emails_saida` vira `entregue`. **Enquanto isso não acontecer, não
   ligue o cron.**
5. **Rode a varredura em modo seco** — `?teste=1` examina e devolve o diagnóstico
   sem reenviar nada. Confira quantas mensagens *seriam* reenviadas antes de
   deixar o cron solto.
6. **Só então agende o cron** de 15 em 15 minutos.

```json
// vercel.json
{ "crons": [ { "path": "/api/cron/email", "schedule": "*/15 * * * *" } ] }
```

### 11.1 A varredura, em ordem

A ordem das etapas **é** a regra de negócio:

```
0. CONFERE O INSTRUMENTO
   Se nenhuma confirmação existe na janela, a varredura NÃO conclui nada —
   nem reenvia, nem mexe no disjuntor. Marca-se "cega" e grava-se o aviso.

1. MARCA COMO PERDIDA a mensagem aceita além da janela (só caminho próprio).

2. REENVIA O DOCUMENTO ORIGINAL pelo provedor de queda, com o mesmo assunto,
   o mesmo HTML e o mesmo reply-to. Sem corpo guardado, degrada para um aviso.
   Esgotadas as tentativas: "desistir" — visível, sem novo envio.

3. REAVALIA O DISJUNTOR com a foto já atualizada.

4. Roda a faxina dos corpos expirados.

5. GRAVA O RESULTADO DA VARREDURA — sempre, inclusive quando cega.
```

A função de varredura recebe o `enviar` **por parâmetro**:

```ts
export async function varrerEntregas(
  enviar: (m: MensagemReenvio) => Promise<{ enviado: boolean; motivo?: string }>,
  agora = new Date()
): Promise<ResultadoVarredura>
```

É o que permite rodar a varredura inteira no teste, sem rede, e é o que dá o modo
seco de graça:

```ts
const enviar = teste
  ? async () => ({ enviado: true as const })
  : (m: MensagemReenvio) => enviarPelaBrevo(m);
```

---

## 12. Leituras operacionais

O que a tela de operação diz, e o que cada estado significa de verdade. **A ordem
de checagem importa.**

| Estado | Nível | O que está acontecendo |
|---|---|---|
| varredura nunca rodou | atenção | Legítimo logo depois de subir. Vira problema se ficar assim: nada é detectado nem reenviado. |
| cron parado > 45 min | **crítico** | A proteção está fora do ar. Vem *antes* da cegueira na ordem de checagem: se o cron morreu, o dado de cegueira também está velho. |
| varredura cega | **crítico** | Sistema intacto e desprotegido ao mesmo tempo. Nada foi reenviado, o disjuntor não se mexeu — de propósito. Confira o segredo e a URL do webhook. |
| disjuntor aberto | atenção | Não é falha: é a proteção agindo. As mensagens estão sendo entregues; o que se perde é o log por mensagem e o controle de bounce do servidor próprio. |
| tudo normal | ok | O que o servidor próprio aceitar e não entregar em 20 minutos é reenviado automaticamente. |

### 12.1 A taxa de entrega, com o denominador certo

O denominador **exclui o que ainda está em trânsito**: contar "aceito há dois
minutos" como não-entregue faria a taxa despencar toda vez que alguém abrisse a
tela logo depois de um envio.

```ts
const decididos = entregues + perdidos + falhas;
const taxaEntrega = decididos === 0 ? null : Math.round((entregues / decididos) * 100);
```

Sem base, devolva **nulo** — nunca 0%, que é indistinguível de falha total.

### 12.2 Sobre abertura e clique

Abertura é **piso e comparação**, nunca medida absoluta: o pixel é bloqueado por
padrão em boa parte dos clientes de e-mail, e o Apple Mail Privacy Protection
carrega **todas** as imagens, o que produz o erro contrário — abertura fantasma.
O **clique** exige ação e é o número em que se decide.

Calcule as taxas **sobre entregues, não sobre enviados**: e-mail que bateu nunca
teve chance de ser aberto, e contá-lo faz uma lista suja parecer campanha ruim —
problemas diferentes, soluções diferentes.

```ts
entrega               = entregues / enviados
abertura              = abriram   / entregues
clique                = clicaram  / entregues
clique_sobre_abertura = clicaram  / abriram    // separa "assunto bom, corpo
                                               // fraco" de "ninguém viu"
```

---

## 13. As decisões que valem repetir

Se o outro time levar só isto, já vale.

- **Separe decisão de efeito colateral.** Todas as regras — o que é perdido,
  quando reenviar, quando abrir o disjuntor — moram num módulo **puro**, sem
  banco e sem rede, e por isso são testáveis de verdade. O acesso ao banco é
  outro arquivo; o driver do provedor é um terceiro.

- **A função de varredura recebe o `enviar` por parâmetro.** É o que permite
  rodar a varredura inteira no teste, sem rede, e é o que dá o modo seco de
  graça.

- **Bounce não se reenvia.** Caixa que não existe pelo primeiro provedor também
  não existe pelo segundo, e insistir queima o segundo caminho também.

- **Falha de leitura do disjuntor devolve "fechado".** Na dúvida, o caminho
  normal. Devolver "aberto" por erro de banco desviaria tudo em silêncio e
  queimaria a cota do segundo provedor por causa de um timeout.

- **Nomeie o driver pelo que ele é.** A função de envio pela Brevo chama
  `enviarPelaBrevo`, não `enviarEmail`: numa lista de imports, `enviarEmail`
  vindo de um arquivo chamado `brevo.ts` faz qualquer pessoa concluir que o
  e-mail sai pela Brevo — e não sai.

- **Todo e-mail que convida a responder precisa de reply-to.** O remetente é um
  `nao-responda@`; sem `responderPara`, a frase "é só responder a este e-mail" é
  mentira. Pior que não convidar a responder é convidar e sumir.

---

## Apêndice · Mapa de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `lib/mailer/postal.ts` | Driver do Postal. Não confia no HTTP 200. |
| `lib/brevo.ts` | Driver da Brevo. Só o "como falar", nada de decisão. |
| `lib/email.ts` | **A porta única.** Escolhe o caminho, envia, registra. |
| `lib/entrega-garantida.ts` | **Puro.** Chave, janela, ação, disjuntor, instrumento, monitor. |
| `lib/entrega-server.ts` | Banco e nada de decisão. Lê/grava disjuntor e saídas; a varredura. |
| `lib/email-eventos.ts` | **Puro.** Tradução dos webhooks e cálculo das taxas. |
| `app/api/email/evento/route.ts` | O webhook — uma porta, dois provedores. |
| `app/api/cron/email/route.ts` | A varredura, a cada 15 minutos. |
| `app/api/dev/testar-email/route.ts` | Teste manual, protegido por segredo. |

Migrations de referência: `0050` (eventos), `0060` (saída + disjuntor),
`0061` (corpo para reenvio + faxina).
