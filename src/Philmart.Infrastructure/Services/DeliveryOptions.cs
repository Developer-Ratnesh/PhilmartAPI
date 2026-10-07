using Microsoft.EntityFrameworkCore;
using Philmart.Application.Registration;
using Philmart.Infrastructure.Persistence;

namespace Philmart.Infrastructure.Services;

internal static class DeliveryOptions
{
    // All active platform methods, or with a Shop, only the ones that Shop has
    // switched on (D009: the buyer picks from what the Shop offers).
    public static async Task<List<DeliveryOptionDTO>> Load(PhilmartContext context, Guid? shopId, CancellationToken cancellationToken)
    {
        List<MethodRow> methods;

        if (shopId == null)
        {
            methods = await context.Database
                .SqlQuery<MethodRow>($@"SELECT ID, Code, Name, MethodKind, RequiresPickupPoint, RequiresAddress, SortOrder
                                        FROM philmart.Sys_DeliveryMethod WHERE Active = 1 AND RetiredAt IS NULL")
                .ToListAsync(cancellationToken);
        }
        else
        {
            methods = await context.Database
                .SqlQuery<MethodRow>($@"SELECT m.ID, m.Code, m.Name, m.MethodKind, m.RequiresPickupPoint, m.RequiresAddress, m.SortOrder
                                        FROM philmart.Sys_DeliveryMethod m
                                        JOIN philmart.Shop_DeliveryMethod sm ON sm.DeliveryMethodID = m.ID
                                        WHERE sm.ShopID = {shopId} AND sm.Enabled = 1 AND m.Active = 1 AND m.RetiredAt IS NULL")
                .ToListAsync(cancellationToken);
        }

        var points = await context.Database
            .SqlQuery<PointRow>($@"SELECT ID, DeliveryMethodID, Name, AddressLine1, City
                                   FROM philmart.Sys_PickupPoint WHERE Active = 1")
            .ToListAsync(cancellationToken);

        var result = new List<DeliveryOptionDTO>();

        foreach (var m in methods.OrderBy(x => x.SortOrder).ThenBy(x => x.Name))
        {
            var dto = new DeliveryOptionDTO();
            dto.ID = m.ID;
            dto.Code = m.Code;
            dto.Name = m.Name;
            dto.MethodKind = m.MethodKind;
            dto.RequiresPickupPoint = m.RequiresPickupPoint;
            dto.RequiresAddress = m.RequiresAddress;

            foreach (var p in points.Where(x => x.DeliveryMethodID == m.ID).OrderBy(x => x.Name))
            {
                var point = new PickupPointDTO();
                point.ID = p.ID;
                point.Name = p.Name;
                point.Address = string.Join(", ", new[] { p.AddressLine1, p.City }.Where(x => !string.IsNullOrWhiteSpace(x)));
                dto.PickupPoints.Add(point);
            }

            result.Add(dto);
        }

        return result;
    }

    private class MethodRow
    {
        public Guid ID { get; set; }

        public string Code { get; set; } = null!;

        public string Name { get; set; } = null!;

        public string MethodKind { get; set; } = null!;

        public bool RequiresPickupPoint { get; set; }

        public bool RequiresAddress { get; set; }

        public int SortOrder { get; set; }
    }

    private class PointRow
    {
        public Guid ID { get; set; }

        public Guid DeliveryMethodID { get; set; }

        public string Name { get; set; } = null!;

        public string? AddressLine1 { get; set; }

        public string? City { get; set; }
    }
}
