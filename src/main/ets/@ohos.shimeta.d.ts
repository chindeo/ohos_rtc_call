declare module '@ohos.shimeta' {
  namespace shimeta {
    function net_getMacAddress(type: string): string;
    function sys_setSystemBootApp(app_param: string): number;
    function sys_getSystemBootApp(): string;
    function sys_setAutoPowerOnOff(
      enable: number,
      week: string,
      onHour: number,
      onMinute: number,
      offHour: number,
      offMinute: number
    ): number;
    function sys_getAutoPowerOnOff(): Promise<string>;
    function sys_doSilentInstallApp(hapPath: string, isRun: number, bundleName: string): number;
  }

  export default shimeta;
}
