var __teclas_templates = {
    "1":[{"text":"CART&Atilde;O<br />PRESENTE","pdvfn":"500","xtype":"teclafuncional","cls":"bt_teclado_y","lin":6,"col":1,"teclado":"1"},{"text":"SERVI&Ccedil;O","codprod":"1927905","xtype":"teclaproduto","cls":"bt_teclado_y","lin":6,"col":2,"teclado":"1"},{"text":"CONSULTA<br />MERCADORIA","pdvfn":"136","xtype":"teclafuncional","cls":"bt_teclado_y","lin":6,"col":3,"teclado":"1"}],
    "2":[{"text":"Canc<br />cupom","evento":"2","xtype":"teclagatilho","cls":"bt_teclado_y","lin":1,"fatorLargura": 2,"col":5,"teclado":"1","autoColeta":null,"monetario":null,"value":null,"autoLabel":null}],
    "4":[{"text":"testeeeeeee","evento":"9","xtype":"teclagatilho","cls":"bt_teclado_y","lin":0,"col":0,"teclado":"1","autoColeta":null,"monetario":null,"value":null,"autoLabel":null},{"text":"TESTE1","evento":"2","xtype":"teclagatilho","cls":"bt_teclado_y","lin":1,"col":0,"teclado":"1","autoColeta":null,"monetario":null,"value":null,"autoLabel":null},{"text":"TESTE10","evento":"7","xtype":"teclagatilho","cls":"bt_teclado_y","lin":2,"col":0,"teclado":"1","autoColeta":true,"monetario":null,"value":null,"autoLabel":"Porcentagem"},{"text":"TESTE11","evento":"16","xtype":"teclagatilho","cls":"bt_teclado_y","lin":3,"col":0,"teclado":"1","autoColeta":true,"monetario":null,"value":null,"autoLabel":"Tipo de venda"}],
    "6":[{"text":"VENDA<br />ESPECIAL<br />TESTE","evento":"16","xtype":"teclagatilho","cls":"bt_teclado_y","lin":0,"col":0,"teclado":"1","autoColeta":true,"monetario":null,"value":null,"autoLabel":"Tipo de venda"}],
    "1000": [
        {
            xtype: 'container',
            defaults: {
                border: 0,
                width: 90,
                height: 50,
                margin: '10 5 0 0',
                cls: "bt_teclado_w",
                /*style: "background-color: yellow !important;",*/
            },
            flex: 1,
            layout: {
                type: 'hbox',
            },
            items: [
                {
                    text: "Informar<br />Quantidade",
                    lin: 6,
                    col: 2,
                    width: 120,
                    teclado: "1",
                    evento: "13",
                    xtype: "teclagatilho",
                    autoColeta: true,
                    monetario: null,
                    value: null,
                    autoLabel: 'Informe a quantidade'},
		   {"text":"Cancelar<br />Item","pdvfn":"1146","xtype":"teclafuncional","cls":"bt_teclado_y","lin":6,"col":3,"teclado":"1"},
		   {"text":"Cancelar<br />Cupom","pdvfn":"1148","xtype":"teclafuncional","cls":"bt_teclado_y","lin":6,"col":4,"teclado":"1"},
		   {"text":"Pesquisa<br />Embalagem","pdvfn":"1123","xtype":"teclafuncional","cls":"bt_teclado_y","lin":6,"col":5,"teclado":"1"}

]
        }],
    "caedu":[{
        opcoes: [
            {
                "habilitado" : 0,
                "text":"Vendedor",
                "evento":"3",
                "xtype":"botaoSimplesCaedu",
                "cls":"bt_menu",
                "fatorLargura": 3,
                "lin":4,
                "col":4,
                "teclado":"1",
                "autoColeta":true,
                "monetario":null,
                "value":null,
                "autoLabel":"Vendedor"
            },
            {
                "habilitado" : 0,
                "text": "Acrescimo",
                "xtype": 'botaoSimplesCaedu',
                "cls": 'bt_menu',
                "fatorLargura": 3,
                "lin": 4,
                "col": 7,
                "teclado": "1",
                "evtoClick": function(obj) {Ext.create('Pdv.view.tela.caedu.componente.dialogo.TelaAcrescimo').show();}
            },
            {
                "habilitado" : 0,
                "text": "NFPDV",
                "pdvfn": "1100",
                "xtype": 'teclafuncional',
                "cls": 'bt_menu',
                "fatorLargura": 3,
                "lin": 5,
                "col": 1,
                "teclado": "1"
            }
        ],
        finalizadora: [
            {
                "text": "Pagamento POS</br>F7",
                "autoLabel": "Valor em POS",
                "codfin" : "7",
                "habilitado" : 1,
                "itemId": 'teclaF7'
            },
            {
                "text": "Finalizadora 8</br>F8",
                "autoLabel": "Finalizadora 8",
                "codfin" : "8",
                "habilitado" : 0,
                "itemId": 'teclaF8'
            },
            {
                "text": "Finalizadora 9</br>F9",
                "autoLabel": "Finalizadora 9",
                "codfin" : "9",
                "habilitado" : 0,
                "itemId": 'teclaF9'
            },
            {
                "text": "Finalizadora 10</br>F10",
                "autoLabel": "Finalizadora 10",
                "codfin" : "10",
                "habilitado" : 0,
                "itemId": 'teclaF10'
            },
            {
                "text": "Finalizadora 11</br>F11",
                "autoLabel": "Finalizadora 11",
                "codfin" : "11",
                "habilitado" : 0,
                "itemId": 'teclaF11'
            },
            {
                "text": "Finalizadora 12</br>F12",
                "autoLabel": "Finalizadora 12",
                "codfin" : "12",
                "habilitado" : 0,
                "itemId": 'teclaF12'
            }
        ]
    }]
}
