import React, { useState } from 'react';
import { Container, Header, Card, CardItem, Label, H1, H2, Subtitle, Content, Button, Item, Input, Icon, Left, Body, Title, Right, Text } from 'native-base';

const BigNumber = require('bignumber.js');

const coefA = new BigNumber('0.6180339887')
const coefB = new BigNumber('0.3819660113')
const ratio = new BigNumber('1.6180339887')

const App = () => {

  const [vals, setVals] = useState({ a: "0", b: "0", c: "" })

  const doCalc = (c) => {
    if (c) {
      a = new BigNumber(c)
        .multipliedBy(coefA)
        .toFixed(0)
        .toString();
      b = new BigNumber(c)
        .multipliedBy(coefB)
        .toFixed(0)
        .toString();
      return setVals({ a, b, c })
    }
    return setVals({ a: "0", b: "0", c: "" })
  }

  return (
    <Container>
      <Header>
        <Left />
        <Body>
          <Title>Golden Ratio</Title>
          <Subtitle>Calculator Lite</Subtitle>
        </Body>
        <Right />
      </Header>
      <Content style={{ flex: 1, width: "100%", height: "100%" }} justifyContent={"center"}>
        <Card style={{ alignSelf: "center", width: "100%" }}>
          <CardItem header>
            <Icon type='Ionicons' name='calculator-outline' />
            <H1>Golden ratio values</H1>
            <Left></Left>
            <Button light onPress={() => doCalc()} style={{ padding: 10 }}>
              <H2>Reset</H2>
            </Button>
          </CardItem>
          <CardItem>
            <Body style={{ flexDirection: "column", backgroundColor: "white" }}>
              <Body style={{ flexDirection: "column", alignContent: "center", backgroundColor: "white", margin: 10 }}>
                <Item>
                  <H1>Whole is: </H1>
                </Item>
                <Item>
                  <Input
                    textAlign="center"
                    placeholder="Enter value"
                    keyboardType="numeric"
                    onChangeText={val => doCalc(val)}
                    value={vals.c}
                    style={{ fontSize: 30 }}
                  />
                </Item>
              </Body>
              <Body style={{ flexDirection: "row", backgroundColor: "white", margin: 10 }}>
                <Body style={{ flex: 1, flexDirection: "column", alignContent: "center", backgroundColor: "white" }}>
                  <H1>Ratios are: </H1>
                  <H1 style={{margin: 10}}>{vals.a + " and " + vals.b}</H1>
                </Body>
              </Body>
            </Body>
          </CardItem>
        </Card>
      </Content>
    </Container>
  );
};

export default App;
