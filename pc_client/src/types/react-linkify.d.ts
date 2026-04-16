declare module "react-linkify" {
  import { ComponentType, ReactNode } from "react";

  interface LinkifyProps {
    children: ReactNode;
    componentDecorator?: (
      decoratedHref: string,
      decoratedText: string,
      key: number,
    ) => ReactNode;
  }

  const Linkify: ComponentType<LinkifyProps>;
  export default Linkify;
}
