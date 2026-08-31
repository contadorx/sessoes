/**
 * `server-only` é resolvido pelo próprio Next durante o build; fora dele o
 * pacote não existe. Este arquivo vazio é o que o Vitest usa no lugar, para que
 * um módulo de servidor possa ser testado como qualquer outro.
 *
 * A garantia real continua sendo a do Next: importar um módulo `server-only`
 * de um componente de cliente quebra a compilação.
 */
export {};
