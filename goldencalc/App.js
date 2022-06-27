import React, { useState } from 'react';
import { Container, Header, Card, CardItem, Label, Subtitle, Content, Button, Item, Input, Icon, Left, Body, Title, Right, Text } from 'native-base';
import { useClipboard } from '@react-native-community/clipboard';

const BigNumber = require('bignumber.js');

const coefA = new BigNumber('0.6180339887')
const coefB = new BigNumber('0.3819660113')
const ratio = new BigNumber('1.6180339887')

const App = () => {

  const [clipboardData, setString] = useClipboard()
  const [vals, setVals] = useState({ a: null, b: null, c: null })

  const doCalc = (a, b, c) => {
    if (a) {
      c = new BigNumber(a)
        .multipliedBy(ratio)
        .toPrecision(10)
        .toString();
      b = new BigNumber(c)
        .multipliedBy(coefB)
        .toPrecision(10)
        .toString(10);
      return setVals({ a, b, c })
    }
    if (b) {
      a = new BigNumber(b)
        .dividedBy(coefB)
        .multipliedBy(coefA)
        .toPrecision(10)
        .toString();
      c = new BigNumber(a)
        .multipliedBy(ratio)
        .toPrecision(10)
        .toString();
      return setVals({ a, b, c })
    }
    if (c) {
      a = new BigNumber(c)
        .multipliedBy(coefA)
        .toPrecision(10)
        .toString();
      b = new BigNumber(c)
        .multipliedBy(coefB)
        .toPrecision(10)
        .toString();
      return setVals({ a, b, c })
    }
    return setVals({ a: null, b: null, c: null })
  }

  return (
    <Container>
      <Header>
        <Left />
        <Body>
          <Title>Golden Ratio</Title>
          <Subtitle>Tech Calculator</Subtitle>
        </Body>
        <Right />
      </Header>
      <Content>
        <Card>
          <CardItem header>
            <Icon type='Ionicons' name='calculator-outline' />
            <Text>Calculator</Text>
            <Left></Left>
            <Button iconCenter onPress={() => doCalc()} transparent style={{ margin: 10 }}>
              <Text>Reset</Text>
            </Button>
          </CardItem>
          <CardItem>
            <Body style={{ flexDirection: "column", backgroundColor: "white" }}>
              <Body style={{ flexDirection: "row", backgroundColor: "white", margin: 10 }}>
                <Body style={{ flex: 1, flexDirection: "row", backgroundColor: "white" }}>
                  <Item>
                    <Label>a =</Label>
                    <Input
                      keyboardType='numeric'
                      value={vals.a}
                      onChangeText={val => doCalc(val, null, null)}
                    />
                    <Button icon transparent onPress={() => doCalc(clipboardData, null, null)}>
                      <Icon type='Ionicons' name='clipboard-outline' />
                    </Button>
                    <Button icon transparent onPress={() => setString(vals.a)}>
                      <Icon type='Ionicons' name='copy' />
                    </Button>
                  </Item>
                </Body>
              </Body>
              <Body style={{ flexDirection: "row", backgroundColor: "white", margin: 10 }}>
                <Item>
                  <Label>b =</Label>
                  <Input
                    keyboardType="numeric"
                    value={vals.b}
                    onChangeText={val => doCalc(null, val, null)}
                  />
                  <Button icon transparent onPress={() => doCalc(null, clipboardData, null)}>
                    <Icon type='Ionicons' name='clipboard-outline' />
                  </Button>
                  <Button icon transparent onPress={() => setString(vals.b)}>
                    <Icon type='Ionicons' name='copy' />
                  </Button>
                </Item>
              </Body>
              <Body style={{ flexDirection: "row", backgroundColor: "white", margin: 10 }}>
                <Item>
                  <Label>c =</Label>
                  <Input
                    keyboardType="numeric"
                    value={vals.c}
                    onChangeText={val => doCalc(null, null, val)}
                  />
                  <Button icon transparent onPress={() => doCalc(null, null, clipboardData)}>
                    <Icon type='Ionicons' name='clipboard-outline' />
                  </Button>
                  <Button icon transparent onPress={() => setString(vals.c)}>
                    <Icon type='Ionicons' name='copy' />
                  </Button>
                </Item>
              </Body>
            </Body>
          </CardItem>
        </Card>
        <Card>
          <CardItem header>
            <Icon type='Ionicons' name='document-outline' />
            <Text>Copy ratio constants to clipboard</Text>
          </CardItem>
          <CardItem>
            <Body>
              <Text></Text>
              <Body style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "center", width: "100%", margin: 5 }}>
                <Text>{coefA.toString()}</Text>
                <Button icon transparent onPress={() => setString(coefA.toString())}>
                  <Icon type='Ionicons' name='copy' />
                </Button>
              </Body>
              <Text></Text>
              <Body style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "center", width: "100%", margin: 5 }}>
                <Text>{coefB.toString()}</Text>
                <Button icon transparent onPress={() => setString(coefB.toString())}>
                  <Icon type='Ionicons' name='copy' />
                </Button>
              </Body>
              <Text></Text>
              <Body style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "center", width: "100%", margin: 5 }}>
                <Text>{ratio.toString()}</Text>
                <Button icon transparent onPress={() => setString(ratio.toString())}>
                  <Icon type='Ionicons' name='copy' />
                </Button>
              </Body>
            </Body>
          </CardItem>
        </Card>
        <Card>
          <CardItem header>
            <Icon type='Ionicons' name='help-circle-outline' />
            <Text>Math</Text>
          </CardItem>
          <CardItem>
            <Body>
              <Text>Formulas used</Text>
              <Text></Text>
              <Text>a * {coefA.toString()} + b * {coefB.toString()} = c</Text>
              <Text></Text>
              <Text>c * (1-1 / {ratio.toString()}) = b</Text>
              <Text></Text>
              <Text>c / {ratio.toString()} = a</Text>
            </Body>
          </CardItem>
        </Card>
        <Card>
          <CardItem header>
            <Icon type='Ionicons' name='information-circle-outline' />
            <Text>Usage</Text>
          </CardItem>
          <CardItem>
            <Body>
              <Text>Put value in any field to calculate parts and whole</Text>
              <Text></Text>
              <Text>Use copy/paste buttons to copy between devices</Text>
            </Body>
          </CardItem>
        </Card>
      </Content>
    </Container>
  );
};

export default App;
