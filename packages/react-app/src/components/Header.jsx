import React from "react";
import { PageHeader } from "antd";

// displays a page header

export default function Header() {
  return (
    <a href="https://github.com/jlw264/farmed-particles" target="_blank" rel="noopener noreferrer">
      <PageHeader
        title="Farmed Particles"
        subTitle="Yield-farming NFTs built on Charged Particles!"
        style={{ cursor: "pointer" }}
      />
    </a>
  );
}
