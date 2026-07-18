import 'package:flutter/material.dart';

double mediaHeight(BuildContext context, double data) {
  return MediaQuery.of(context).size.height * data;
}

double mediaWidth(BuildContext context, double data) {
  return MediaQuery.of(context).size.width * data;
}
