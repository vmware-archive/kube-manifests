// Helper for creating AWS CNAME records for kube-cert-manager.  See
// comments in `kube-cert-manager.jsonnet`.

local cname = std.extVar("cname");
local value = std.extVar("value");

{
  Changes: [
    {
      Action: "UPSERT",
      ResourceRecordSet: {
        Name: cname,
        Type: "CNAME",
        TTL: 300,
        ResourceRecords: [
          { Value: if std.endsWith(value, ".") then value else value + "." },
        ],
      },
    },
  ],
}
